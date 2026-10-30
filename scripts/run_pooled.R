# Pooled person-mean-centered model: one glmnet per feature set x outcome,
# trained on all people's data, evaluated per person.
# Numeric features: within = x - person_mean, between = person_mean.
# Factor (binary) features: kept as numeric 0/1 (no centering).
# 10-fold CV on pooled training set to tune lambda; alpha = 0.5.
# Usage: Rscript scripts/run_pooled.R <rebuilt_dir> <out_dir>
suppressPackageStartupMessages({
  library(dplyr); library(purrr); library(stringr)
  library(glmnet); library(yardstick)
})

args <- commandArgs(TRUE)
rb <- args[1]; outdir <- args[2]
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

keys <- sub("\\.RData$", "", list.files(file.path(rb, "04-data/04-test-data")))
key_parts <- str_match(keys, "^(\\d+)_(.+)_(.+)_(.+)_(.+)$")
splits <- tibble(
  key = keys, SID = key_parts[,2], outcome = key_parts[,3],
  group = key_parts[,4], set = key_parts[,5], time = key_parts[,6]
)
combos <- splits %>% distinct(outcome, group, set, time)
cat(sprintf("Running %d feature-set combos sequentially\n", nrow(combos)))

all_res <- list()
for (ci in seq_len(nrow(combos))) {
  co <- combos[ci, ]
  combo_key <- paste(co$outcome, co$group, co$set, co$time, sep = "_")
  outfile <- file.path(outdir, paste0(combo_key, ".rds"))
  if (file.exists(outfile)) {
    cat(sprintf("[skip] %s\n", combo_key))
    all_res[[ci]] <- readRDS(outfile); next
  }

  ks <- splits %>% filter(outcome == co$outcome, group == co$group,
                           set == co$set, time == co$time)

  train_list <- list(); test_list <- list()
  for (i in seq_len(nrow(ks))) {
    k <- ks$key[i]; sid <- ks$SID[i]
    load(file.path(rb, "04-data/03-train-data", paste0(k, ".RData")))
    load(file.path(rb, "04-data/04-test-data", paste0(k, ".RData")))
    d_train$SID <- sid; d_test$SID <- sid
    train_list[[i]] <- d_train; test_list[[i]] <- d_test
  }

  common_cols <- Reduce(intersect, lapply(train_list, names))
  common_cols <- Reduce(intersect, c(list(common_cols), lapply(test_list, names)))
  train_all <- bind_rows(lapply(train_list, function(d) d[, common_cols]))
  test_all <- bind_rows(lapply(test_list, function(d) d[, common_cols]))

  feat_cols <- setdiff(common_cols, c("Full_Date", "o_value", "SID"))
  num_cols <- feat_cols[sapply(train_all[feat_cols], is.numeric)]
  fac_cols <- feat_cols[sapply(train_all[feat_cols], is.factor)]

  # Person-mean center numeric features
  person_means <- train_all %>%
    group_by(SID) %>%
    summarize(across(all_of(num_cols), ~ mean(.x, na.rm = TRUE)), .groups = "drop")

  center_fn <- function(d, pmeans) {
    if (length(num_cols) == 0) return(d)
    within_cols <- list(); between_cols <- list()
    for (col in num_cols) {
      pm <- pmeans[[col]][match(d$SID, pmeans$SID)]
      within_cols[[paste0(col, "_w")]] <- d[[col]] - pm
      between_cols[[paste0(col, "_b")]] <- pm
    }
    bind_cols(d, as_tibble(within_cols), as_tibble(between_cols))
  }

  train_c <- center_fn(train_all, person_means)
  test_c <- center_fn(test_all, person_means)

  new_num <- if (length(num_cols) > 0) c(paste0(num_cols, "_w"), paste0(num_cols, "_b")) else character(0)
  x_col_names <- c(new_num, fac_cols)

  make_x <- function(d) {
    m <- d[, x_col_names, drop = FALSE]
    for (fc in fac_cols) m[[fc]] <- as.numeric(as.character(m[[fc]]))
    as.matrix(m)
  }

  x_train <- make_x(train_c)
  y_train <- as.numeric(as.character(train_c$o_value))

  col_sd <- apply(x_train, 2, sd, na.rm = TRUE)
  keep <- !is.na(col_sd) & col_sd > 0
  x_train <- x_train[, keep, drop = FALSE]
  keep_names <- colnames(x_train)

  na_rows <- rowSums(is.na(x_train)) > 0
  x_train <- x_train[!na_rows, , drop = FALSE]
  y_train <- y_train[!na_rows]

  if (length(unique(y_train)) < 2 || nrow(x_train) < 20) {
    cat(sprintf("[skip-degenerate] %s\n", combo_key))
    all_res[[ci]] <- tibble(); next
  }

  nf <- min(10, floor(nrow(x_train) / 10))
  if (nf < 3) nf <- 3
  fit <- tryCatch(
    cv.glmnet(x_train, y_train, family = "binomial", alpha = 0.5,
              type.measure = "class", nfolds = nf),
    error = function(e) { cat(sprintf("[error] %s: %s\n", combo_key, e$message)); NULL }
  )
  if (is.null(fit)) { all_res[[ci]] <- tibble(); next }

  results <- map_dfr(unique(test_c$SID), function(sid) {
    idx <- test_c$SID == sid
    x_te <- make_x(test_c[idx, , drop = FALSE])
    # align columns
    missing <- setdiff(keep_names, colnames(x_te))
    if (length(missing) > 0) {
      fill <- matrix(0, nrow = nrow(x_te), ncol = length(missing),
                     dimnames = list(NULL, missing))
      x_te <- cbind(x_te, fill)
    }
    x_te <- x_te[, keep_names, drop = FALSE]
    na_r <- rowSums(is.na(x_te)) > 0
    x_te <- x_te[!na_r, , drop = FALSE]
    y_te <- as.numeric(as.character(test_c$o_value[idx]))[!na_r]

    if (length(y_te) < 1) return(tibble())
    prob <- as.numeric(predict(fit, x_te, s = "lambda.min", type = "response"))
    pred <- ifelse(prob > 0.5, 1, 0)
    acc <- mean(pred == y_te)
    auc <- if (n_distinct(y_te) < 2) NA_real_ else
      roc_auc_vec(factor(y_te, levels = c(0,1)), prob, event_level = "second")
    tibble(SID = sid, outcome = co$outcome, group = co$group, set = co$set,
           time = co$time, acc = acc, auc = auc, n_test = length(y_te),
           model = "pooled_glmnet", lambda = fit$lambda.min)
  })

  saveRDS(results, outfile)
  cat(sprintf("[done] %s: %d people, mean AUC = %.3f\n", combo_key, nrow(results),
              mean(results$auc, na.rm = TRUE)))
  all_res[[ci]] <- results
}

all_res <- bind_rows(all_res)
write.csv(all_res, file.path(outdir, "pooled_results.csv"), row.names = FALSE)
cat(sprintf("\nTotal: %d person-split results across %d combos\n",
            nrow(all_res), nrow(combos)))

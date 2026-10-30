# Re-run Beck & Jackson's BISCWIT models (03-biscwit.Rmd, biscwit_fun) on the
# shipped train/test splits, saving only test metrics and the chosen n items.
# Also records AUC with the event level set to "1" (roc_auc_event1): the
# original roc_auc() call uses yardstick's default first level ("0") although
# higher predictions mean outcome 1.
# --fixed picks the item count with the highest (signed) validation r instead of
#   the highest |r|
# Usage: Rscript scripts/run_biscwit.R <repo> <out_dir> <workers> [max_models] [--fixed]

all_args <- commandArgs(trailingOnly = TRUE)
fixed <- "--fixed" %in% all_args
args <- grep("^--", all_args, value = TRUE, invert = TRUE)
res_path <- normalizePath(args[1])
out_dir <- args[2]
workers <- as.integer(args[3])
# one BLAS thread per worker and 4 cores left free: OpenBLAS otherwise starts a
# thread per core in every worker, and that oversubscription coincided with two
# watchdog kernel panics (Oct 28 and 30, 2026)
Sys.setenv(OPENBLAS_NUM_THREADS = 1, OMP_NUM_THREADS = 1, VECLIB_MAXIMUM_THREADS = 1)
workers <- min(workers, max(1L, parallel::detectCores() - 4L))
max_models <- if (length(args) >= 4) as.integer(args[4]) else Inf
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(purrr); library(tibble)
  library(psych); library(rsample); library(yardstick); library(furrr)
})

# verbatim from 03-biscwit.Rmd
biscwit_call <- function(x, nitem){
  x_train <- training(x) %>%
    select(o_value, everything()) %>%
    mutate_if(is.factor, ~as.numeric(as.character(.))) %>%
    unclass() %>%
    data.frame()
  bs <- bestScales(x = x_train, criteria = "o_value", n.item = nitem, n.iter = 1)
  mR <- bs$R
  mR[!names(mR) %in% str_remove(bs$best.keys$o_value, "-")] <- 0
  mR <- as.matrix(mR); colnames(mR) <- "o_value"
  x_test <- testing(x) %>%
    select(o_value, everything()) %>%
    mutate_if(is.factor, ~as.numeric(as.character(.))) %>%
    unclass() %>%
    data.frame()
  scores <- scoreWtd(mR, x_test)
  r <- cor(scores, as.numeric(as.character(testing(x)$o_value)))
  return(list(bs = bs, r = r))
}

biscwit_fun <- function(sid, outcome, group, set, time) {
  key <- paste(sid, outcome, group, set, time, sep = "_")
  out_file <- file.path(out_dir, paste0(key, ".rds"))
  if (file.exists(out_file)) return(TRUE)

  load(sprintf("%s/04-data/03-train-data/%s.RData", res_path, key))
  x_train <- d_train %>%
    arrange(Full_Date) %>%
    select(-Full_Date) %>%
    select(o_value, everything()) %>%
    mutate_if(is.factor, ~as.numeric(as.character(.))) %>%
    unclass() %>%
    data.frame()

  init <- ceiling(nrow(d_train)/3)
  d_train_cv <- rolling_origin(x_train, initial = init, assess = 5, skip = 1, cumulative = TRUE)

  tune_res <- d_train_cv %>%
    mutate(nitem = map(splits, ~seq(3, ncol(training(.)) - 1, 3))) %>%
    unnest(nitem) %>%
    mutate(cv = map2(splits, nitem, possibly(biscwit_call, NA_real_))) %>%
    filter(!is.na(cv)) %>%
    mutate(error = map_dbl(cv, ~(.)$r))

  # note abs(): a strongly negative validation correlation can win
  best_biscwit <- tune_res %>%
    group_by(nitem) %>%
    summarize(merror = fisherz2r(mean(fisherz(error), na.rm = T))) %>%
    arrange(desc(if (fixed) merror else abs(merror))) %>%
    slice_head(n = 1)

  final_biscwit <- bestScales(x = x_train, criteria = "o_value", n.item = best_biscwit$nitem, n.iter = 1)
  mR <- final_biscwit$R; mR <- mR[!names(mR) == "o_value"]
  mR[!names(mR) %in% str_remove(final_biscwit$best.keys$o_value, "-")] <- 0
  mR <- as.matrix(mR); colnames(mR) <- "o_value"

  load(sprintf("%s/04-data/04-test-data/%s.RData", res_path, key))
  x_test <- d_test %>%
    arrange(Full_Date) %>%
    select(o_value, everything(), -Full_Date) %>%
    mutate_if(is.factor, ~as.numeric(as.character(.))) %>%
    unclass() %>%
    data.frame()

  scores_best <- scoreWtd(mR, x_train)
  scores_best_test <- scoreWtd(mR, x_test)
  mean_biscuit <- mean(scores_best, na.rm = T)
  sd_biscuit   <- sd(  scores_best, na.rm = T)
  multiple_R <- cor(scores_best, x_train$o_value, use = "pairwise")
  mean_data <- mean(x_train$o_value, na.rm = T)
  sd_data   <- sd(  x_train$o_value, na.rm = T)
  scores_best.z_test <- c((scores_best_test - mean_biscuit) / sd_biscuit)
  value_test <- ( c(multiple_R) * scores_best.z_test * sd_data ) + mean_data
  temp <- data.frame(crit_actual = x_test$o_value, crit_predicted = value_test)

  value_accuracy <- mean(ifelse((temp$crit_predicted >= .5 & temp$crit_actual == 1) |
                                (temp$crit_predicted < .5 & temp$crit_actual == 0), 1, 0), na.rm = T)
  auc <- function(level) {
    if (sd(temp$crit_actual) == 0) return(NA_real_)
    roc_auc(temp %>% mutate(crit_actual = as.factor(crit_actual)),
            truth = crit_actual, crit_predicted, event_level = level)$.estimate
  }

  res <- tibble(.metric = c("roc_auc", "accuracy", "roc_auc_event1"),
                .estimate = c(auc("first"), value_accuracy, auc("second"))) %>%
    mutate(SID = sid, outcome = outcome, group = group, set = set, time = time,
           nitem = best_biscwit$nitem, cv_r = best_biscwit$merror,
           n_train = nrow(x_train), n_test = nrow(x_test))
  saveRDS(res, out_file)
  TRUE
}

jobs <- tibble(file = list.files(sprintf("%s/04-data/02-model-data", res_path))) %>%
  mutate(file = str_remove(file, "\\.RData$")) %>%
  separate(file, c("SID", "outcome", "group", "set", "time"), sep = "_")
if (is.finite(max_models)) jobs <- head(jobs, max_models)
cat(sprintf("%d models, %d workers\n", nrow(jobs), workers))

plan(multisession, workers = workers)
t0 <- Sys.time()
status <- future_pmap_chr(
  jobs,
  function(SID, outcome, group, set, time) {
    r <- tryCatch(biscwit_fun(SID, outcome, group, set, time),
                  error = function(e) conditionMessage(e))
    if (isTRUE(r)) "ok" else paste("ERROR:", r)
  },
  .options = furrr_options(seed = NULL, globals = c("res_path", "out_dir", "biscwit_fun", "biscwit_call", "fixed"),
                           packages = c("dplyr", "tidyr", "stringr", "purrr", "psych", "rsample", "yardstick"))
)
jobs$status <- status
cat(sprintf("done in %.1f min; ok = %d, errors = %d\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")),
            sum(status == "ok"), sum(status != "ok")))
errs <- filter(jobs, status != "ok")
if (nrow(errs)) {
  write.csv(errs, file.path(out_dir, "..", "biscwit_errors.csv"), row.names = FALSE)
  print(count(errs, status, sort = TRUE), n = 10)
}

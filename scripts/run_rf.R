# Re-run Beck & Jackson's random-forest models (04-random-forest.Rmd, rf_fun).
# RF builds its own split from 04-data/02-model-data (log + differencing, lag-1
# embedding), so it does not use the shipped train/test files.
# --lag= sets which predictors are kept after embedding (rows are unchanged, so
# test sets match across modes):
#   full     (default) as in the original
#   no_lag   drop o_value_2, the outcome's value at the current beep
#   lag_only keep only o_value_2 (pure autocorrelation model)
#   no_same_survey  drop every *_2 column. The shipped o_value is the outcome of
#            the previous beep, so *_2 features come from the same survey as the
#            label (concurrent association, not prediction)
# --fixed log-transforms only columns that are all > 0 (the original also logs
#   0/1 items missing from dummy_vars, giving -Inf/NaN rows that drop_na() removes)
# Usage: Rscript scripts/run_rf.R <repo> <out_dir> <workers> [max_models] [--lag=full|no_lag|lag_only] [--fixed]

all_args <- commandArgs(trailingOnly = TRUE)
lag_mode <- sub("--lag=", "", c(grep("^--lag=", all_args, value = TRUE), "--lag=full")[1])
stopifnot(lag_mode %in% c("full", "no_lag", "lag_only", "no_same_survey"))
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
  library(plyr)
  library(dplyr); library(tidyr); library(stringr); library(purrr); library(tibble)
  library(tidymodels); library(ranger); library(furrr)
})

# verbatim from 04-random-forest.Rmd
dummy_vars <- c("o_value", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
                , "morning", "midday", "evening", "night", "argument"
                , "interacted", "lostSmthng", "late", "frgtSmthng", "brdSWk"
                , "excSWk", "AnxSWk", "tired", "sick", "sleeping", "class"
                , "music", "internet", "TV", "study")

time_vars <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
               , "morning", "midday", "evening", "night"
               , "sin2p", "sin1p", "cos2p", "cos1p"
               , "cub", "linear", "quad")

rf_fun <- function(sid, outcome, group, set, time) {
  key <- paste(sid, outcome, group, set, time, sep = "_")
  out_file <- file.path(out_dir, paste0(key, ".rds"))
  if (file.exists(out_file)) return(TRUE)

  load(sprintf("%s/04-data/02-model-data/%s.RData", res_path, key))
  # differencing and box-cox
  d <- d %>% mutate_if(is.factor, ~as.numeric(as.character(.)))
  log_ok <- if (fixed) function(x) if (min(x, na.rm = TRUE) > 0) log(x) else x else log
  d <- d %>%
    mutate_at(vars(-one_of(c(dummy_vars, time_vars)), -Full_Date), log_ok) %>%
    mutate_at(vars(-one_of(c(dummy_vars, time_vars)), -Full_Date), ~. - lag(.))
  # time delay embedding
  d_mbd <- map(d %>% select(-Full_Date, -one_of(time_vars)), ~embed(., 2)) %>% ldply(.) %>%
    group_by(.id) %>%
    mutate(beep = 1:n()) %>%
    ungroup() %>%
    pivot_wider(names_from = ".id"
                , names_glue = "{.id}_{.value}"
                , values_from = c("1", "2")) %>%
    bind_cols(d[-1,] %>% select(Full_Date)) %>%
    select(-beep)

  d_mbd <- d_mbd %>%
    full_join(d %>% select(Full_Date, one_of(time_vars)), by = "Full_Date") %>%
    mutate_at(vars(contains(dummy_vars)), factor) %>%
    drop_na()
  if (lag_mode == "no_lag") d_mbd <- select(d_mbd, -o_value_2)
  if (lag_mode == "lag_only") d_mbd <- select(d_mbd, Full_Date, o_value_1, o_value_2)
  if (lag_mode == "no_same_survey") d_mbd <- select(d_mbd, -ends_with("_2"))

  d_split <- initial_time_split(d_mbd, prop = 0.75)
  d_train <- training(d_split)
  d_train <- d_train %>% arrange(lubridate::ymd_hm(Full_Date)) %>% select(-Full_Date)

  init <- ceiling(nrow(d_train)/3)
  d_train_cv <- rolling_origin(d_train, initial = init, assess = 5, skip = 1, cumulative = TRUE)

  mod_recipe <- recipe(o_value_1 ~ ., data = d_train) %>%
    # contains(dummy_vars) also matches the outcome o_value_1; when it is constant in
    # a fold, the original drops the outcome and current tune fails the whole model
    step_zv(all_numeric(), contains(dummy_vars), contains(time_vars), -all_outcomes()) %>%
    step_dummy(all_nominal(), -all_outcomes())
  # with a single predictor, step_nzv could leave none
  if (lag_mode != "lag_only") mod_recipe <- step_nzv(mod_recipe, all_predictors(), unique_cut = 35)

  tune_spec <- rand_forest(mtry = tune(), trees = 1000, min_n = tune()) %>%
    set_engine("ranger", importance = "permutation") %>%
    set_mode("classification")

  set.seed(345)
  rf_wf <- workflow() %>% add_model(tune_spec) %>% add_recipe(mod_recipe)
  set.seed(345)
  tune_res <- tune_grid(rf_wf, resamples = d_train_cv, grid = 20)

  best_rf <- select_best(tune_res, metric = "accuracy")
  final_wf <- finalize_workflow(rf_wf, best_rf)
  # last_fit() needs Full_Date dropped from the split data, as the training set was
  # (row order must stay as is: the split's indices point into it)
  d_split$data <- d_split$data %>% select(-Full_Date)
  final_fit <- last_fit(final_wf, d_split)

  res <- collect_metrics(final_fit, summarize = TRUE) %>%
    select(.metric, .estimate) %>%
    mutate(SID = sid, outcome = outcome, group = group, set = set, time = time,
           mtry = best_rf$mtry, min_n = best_rf$min_n,
           n_train = nrow(d_train), n_test = nrow(testing(d_split)),
           test_positives = sum(testing(d_split)$o_value_1 == "1"))
  saveRDS(res, out_file)
  TRUE
}

jobs <- tibble(file = list.files(sprintf("%s/04-data/02-model-data", res_path))) %>%
  mutate(file = str_remove(file, "\\.RData$")) %>%
  separate(file, c("SID", "outcome", "group", "set", "time"), sep = "_")
if (is.finite(max_models)) jobs <- head(jobs, max_models)
cat(sprintf("%d models, %d workers, lag = %s, fixed = %s\n", nrow(jobs), workers, lag_mode, fixed))

plan(multisession, workers = workers)
t0 <- Sys.time()
status <- future_pmap_chr(
  jobs,
  function(SID, outcome, group, set, time) {
    r <- tryCatch(rf_fun(SID, outcome, group, set, time),
                  error = function(e) conditionMessage(e))
    if (isTRUE(r)) "ok" else paste("ERROR:", r)
  },
  .options = furrr_options(seed = NULL, globals = c("res_path", "out_dir", "dummy_vars", "time_vars", "rf_fun", "lag_mode", "fixed"),
                           packages = c("plyr", "dplyr", "tidyr", "purrr", "tidymodels", "ranger"))
)
jobs$status <- status
cat(sprintf("done in %.1f min; ok = %d, errors = %d\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")),
            sum(status == "ok"), sum(status != "ok")))
errs <- filter(jobs, status != "ok")
if (nrow(errs)) {
  write.csv(errs, file.path(out_dir, "..", "rf_errors.csv"), row.names = FALSE)
  print(count(errs, status, sort = TRUE), n = 10)
}

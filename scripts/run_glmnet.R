# Re-run Beck & Jackson's elastic-net models (02-elastic-net.Rmd, elnet_fun) on the
# shipped train/test splits, saving only test metrics and chosen hyperparameters.
# Usage: Rscript scripts/run_glmnet.R <repo> <out_dir> <workers> [max_models]

args <- commandArgs(trailingOnly = TRUE)
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
  library(tidymodels); library(glmnet); library(furrr)
})

# copied verbatim from 02-elastic-net.Rmd (note "Tues": the column is "Tue")
dummy_vars <- c("o_value", "Mon", "Tues", "Wed", "Thu", "Fri", "Sat", "Sun"
                , "morning", "midday", "evening", "night", "argument"
                , "interacted", "lostSmthng", "late", "frgtSmthng", "brdSWk"
                , "excSWk", "AnxSWk", "tired", "sick", "sleeping", "class"
                , "music", "internet", "TV", "study")
# "Tues" never matches, leaving Tue as a factor that current glmnet rejects
# ("non-numeric column"); dummy-code it as clearly intended
dummy_vars <- c(dummy_vars, "Tue")

elnet_fun <- function(sid, outcome, group, set, time) {
  key <- paste(sid, outcome, group, set, time, sep = "_")
  out_file <- file.path(out_dir, paste0(key, ".rds"))
  if (file.exists(out_file)) return(TRUE)

  load(sprintf("%s/04-data/03-train-data/%s.RData", res_path, key))
  d_train <- d_train %>% arrange(Full_Date) %>% select(-Full_Date)
  # `night` is always 0 (cleaning bug: Hour >= 22 & Hour < 5); current recipes
  # errors on one-level factors where 2021 versions let them through, so drop
  # any constant factor (it carries no information either way)
  d_train <- d_train %>% select(-where(~ is.factor(.x) && nlevels(droplevels(.x)) < 2), o_value)

  d_train_cv <- rolling_origin(d_train, initial = 15, assess = 1, cumulative = TRUE)

  mod_recipe <- recipe(o_value ~ ., data = d_train) %>%
    step_dummy(any_of(dummy_vars), -all_outcomes()) %>%
    step_zv(all_numeric()) %>%
    step_normalize(all_numeric())
  # original ends with prep(training = d_train, retain = TRUE); current workflows
  # rejects trained recipes, and older versions re-prepped per resample anyway

  tune_spec <- logistic_reg(penalty = tune(), mixture = tune()) %>%
    set_engine("glmnet") %>%
    set_mode("classification")

  elnet_grid <- grid_regular(penalty(), mixture(), levels = 10)
  set.seed(345)
  elnet_wf <- workflow() %>% add_model(tune_spec) %>% add_recipe(mod_recipe)

  elnet_res <- elnet_wf %>%
    tune_grid(resamples = d_train_cv, grid = elnet_grid,
              control = control_resamples(save_pred = TRUE))

  best_elnet <- select_best(elnet_res, metric = "accuracy")
  final_wf <- finalize_workflow(elnet_wf, best_elnet)

  load(sprintf("%s/04-data/04-test-data/%s.RData", res_path, key))
  final_fit <- last_fit(final_wf, d_split)

  res <- collect_metrics(final_fit, summarize = TRUE) %>%
    select(.metric, .estimate) %>%
    mutate(SID = sid, outcome = outcome, group = group, set = set, time = time,
           penalty = best_elnet$penalty, mixture = best_elnet$mixture,
           n_train = nrow(d_train), n_test = nrow(testing(d_split)))
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
    r <- tryCatch(elnet_fun(SID, outcome, group, set, time),
                  error = function(e) conditionMessage(e))
    if (isTRUE(r)) "ok" else paste("ERROR:", r)
  },
  .options = furrr_options(seed = NULL, globals = c("res_path", "out_dir", "dummy_vars", "elnet_fun"),
                           packages = c("dplyr", "tidyr", "tidymodels", "glmnet"))
)
jobs$status <- status
cat(sprintf("done in %.1f min; ok = %d, errors = %d\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")),
            sum(status == "ok"), sum(status != "ok")))
errs <- filter(jobs, status != "ok")
if (nrow(errs)) {
  write.csv(errs, file.path(out_dir, "..", "glmnet_errors.csv"), row.names = FALSE)
  print(count(errs, status, sort = TRUE), n = 10)
}

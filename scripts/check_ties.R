# For one model, count how many tuning-grid points tie on CV accuracy and how much
# the test AUC varies across those tied candidates.
suppressPackageStartupMessages({library(dplyr); library(tidymodels); library(glmnet)})
args <- commandArgs(trailingOnly = TRUE); res_path <- args[1]; key <- args[2]
load(sprintf("%s/04-data/03-train-data/%s.RData", res_path, key))
d_train <- d_train %>% arrange(Full_Date) %>% select(-Full_Date)
cv <- rolling_origin(d_train, initial = 15, assess = 1, cumulative = TRUE)
rec <- recipe(o_value ~ ., data = d_train) %>% step_dummy(all_nominal_predictors()) %>%
  step_zv(all_numeric()) %>% step_normalize(all_numeric())
wf <- workflow() %>% add_recipe(rec) %>% add_model(logistic_reg(penalty = tune(), mixture = tune()) %>% set_engine("glmnet"))
res <- tune_grid(wf, cv, grid = grid_regular(penalty(), mixture(), levels = 10))
acc <- collect_metrics(res) %>% filter(.metric == "accuracy")
tied <- acc %>% filter(mean == max(mean))
cat(sprintf("%s: %d of %d grid points tie for best CV accuracy (%.3f)\n", key, nrow(tied), nrow(acc), max(acc$mean)))
load(sprintf("%s/04-data/04-test-data/%s.RData", res_path, key))
aucs <- sapply(seq_len(nrow(tied)), function(i) {
  f <- last_fit(finalize_workflow(wf, tied[i, c("penalty", "mixture")]), d_split)
  collect_metrics(f) %>% filter(.metric == "roc_auc") %>% pull(.estimate)
})
cat("test AUC across tied candidates:\n"); print(summary(aucs)); print(table(round(aucs, 2)))

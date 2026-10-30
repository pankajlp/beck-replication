# Accuracy of a no-features baseline: predict each participant's most common
# training-set outcome for every test observation, vs. a model's test accuracy.
# RF builds its own split, so for RF the baseline is "always predict 0" on its
# test set (from the counts run_rf.R saves); 0 is the training majority in the
# shipped splits for nearly everyone (printed below).
# Usage: Rscript scripts/majority_baseline.R <repo> <published RData> <rerun_dir> [model]
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(purrr); library(rsample)})
args <- commandArgs(trailingOnly = TRUE); repo <- args[1]
model_name <- if (length(args) >= 4) args[4] else "glmnet"
load(args[2])
pub <- unnest(sum_res, data) %>%
  filter(model == model_name, outcome %in% c("lonely", "prcrst"), .metric == "accuracy") %>%
  select(SID, outcome, group, set, time, published = .estimate)
rerun_all <- bind_rows(lapply(list.files(args[3], pattern = "rds$", full.names = TRUE), readRDS))
rerun <- rerun_all %>%
  filter(.metric == "accuracy") %>% select(SID, outcome, group, set, time, rerun = .estimate)

base <- tibble(key = sub("\\.RData$", "", list.files(sprintf("%s/04-data/04-test-data", repo)))) %>%
  separate(key, c("SID", "outcome", "group", "set", "time"), sep = "_", remove = FALSE)
base_info <- map_dfr(base$key, function(k) {
  load(sprintf("%s/04-data/03-train-data/%s.RData", repo, k))
  load(sprintf("%s/04-data/04-test-data/%s.RData", repo, k))
  maj <- names(which.max(table(d_train$o_value)))
  tibble(train_majority = maj, majority = mean(as.character(testing(d_split)$o_value) == maj))
})
base <- bind_cols(base, base_info)
cat(sprintf("Training majority class is 0 in %.1f%% of shipped splits\n", 100 * mean(base$train_majority == "0")))
if (model_name == "rf") {
  base <- rerun_all %>% filter(.metric == "accuracy") %>%
    transmute(SID, outcome, group, set, time, majority = 1 - test_positives / n_test) %>%
    left_join(select(base, SID, outcome, group, set, time, key), ., by = c("SID", "outcome", "group", "set", "time"))
}

d <- base %>% left_join(pub, by = c("SID", "outcome", "group", "set", "time")) %>%
  left_join(rerun, by = c("SID", "outcome", "group", "set", "time"))
cat(sprintf("Test accuracy: %s vs always predicting the training majority class\n", model_name))
d %>% group_by(outcome) %>%
  # comparisons first: summarize() would otherwise see the already-averaged columns
  summarize(models = sum(!is.na(majority)),
            pub_above = mean(published > majority + 1e-9, na.rm = TRUE),
            pub_tie = mean(abs(published - majority) < 1e-9, na.rm = TRUE),
            pub_below = mean(published < majority - 1e-9, na.rm = TRUE),
            rerun_above = mean(rerun > majority + 1e-9, na.rm = TRUE),
            rerun_tie = mean(abs(rerun - majority) < 1e-9, na.rm = TRUE),
            rerun_below = mean(rerun < majority - 1e-9, na.rm = TRUE),
            majority_acc = mean(majority, na.rm = TRUE),
            published_acc = mean(published, na.rm = TRUE), rerun_acc = mean(rerun, na.rm = TRUE)) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% t() %>% print(quote = FALSE)
write.csv(d, file.path(args[3], "..", paste0(model_name, "_majority_baseline.csv")), row.names = FALSE)

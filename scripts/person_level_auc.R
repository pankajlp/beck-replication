# Is mean test AUC above chance, treating participants as the unit?
# Averages each participant's AUC over their feature sets, then t-tests vs .5,
# for published results and each rerun.
# Usage: Rscript scripts/person_level_auc.R <published RData> <derived_dir>
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
args <- commandArgs(trailingOnly = TRUE)
load(args[1]); dir <- args[2]
read_rerun <- function(sub, metric = "roc_auc") bind_rows(lapply(list.files(file.path(dir, sub), pattern = "rds$", full.names = TRUE), readRDS)) %>%
  filter(.metric == metric) %>% select(SID, outcome, est = .estimate)
pub <- unnest(sum_res, data) %>% filter(outcome %in% c("lonely", "prcrst"), .metric == "roc_auc")
sources <- list(
  "published glmnet"            = pub %>% filter(model == "glmnet") %>% select(SID, outcome, est = .estimate),
  "published BISCWIT"           = pub %>% filter(model == "biscwit") %>% select(SID, outcome, est = .estimate),
  "published RF"                = pub %>% filter(model == "rf") %>% select(SID, outcome, est = .estimate),
  "rerun glmnet"                = read_rerun("glmnet"),
  "rerun BISCWIT (as coded)"    = read_rerun("biscwit"),
  "rerun BISCWIT (event = 1)"   = read_rerun("biscwit", "roc_auc_event1"),
  "rerun RF"                    = read_rerun("rf"),
  "rerun RF, no lagged outcome" = read_rerun("rf_no_lag"),
  "rerun RF, lagged outcome only" = read_rerun("rf_lag_only"),
  "rerun RF, no same-survey features" = read_rerun("rf_no_same_survey")
)
res <- bind_rows(lapply(names(sources), function(nm) {
  sources[[nm]] %>% filter(!is.na(est)) %>%
    group_by(outcome, SID) %>% summarize(auc = mean(est), .groups = "drop") %>%
    group_by(outcome) %>%
    summarize(source = nm, N = n(), mean = mean(auc),
              lo = t.test(auc, mu = .5)$conf.int[1], hi = t.test(auc, mu = .5)$conf.int[2],
              p = t.test(auc, mu = .5)$p.value, .groups = "drop")
}))
res %>% arrange(outcome) %>% mutate(across(c(mean, lo, hi), ~ round(.x, 3)), p = signif(p, 2)) %>%
  as.data.frame() %>% print()
write.csv(res, file.path(dir, "person_level_auc.csv"), row.names = FALSE)

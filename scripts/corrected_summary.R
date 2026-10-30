# Summarize the corrected-split reruns against three benchmarks:
#   - majority class: accuracy of always predicting the test set's majority class
#     (generous: it peeks at the test set) and the training set's majority class
#   - chance: person-level mean AUC vs .5 (participants as the unit)
#   - persistence: AUC of using the current beep's outcome as the score for the
#     next beep's outcome, on the same test rows
# Test sets with one outcome class have no AUC and are left out of AUC summaries.
# Usage: Rscript scripts/corrected_summary.R <rebuilt> <corrected_results_dir>
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(purrr); library(yardstick)})
a <- commandArgs(TRUE); rb <- a[1]; dir <- a[2]
labels <- read.csv(file.path(rb, "labels.csv"), colClasses = c(SID = "character"))
keys <- sub("\\.RData$", "", list.files(file.path(rb, "04-data/04-test-data")))

auc1 <- function(truth, score) {
  if (n_distinct(truth) < 2) return(NA_real_)
  roc_auc_vec(factor(truth, levels = c(0, 1)), score, event_level = "second")
}
bench <- map_dfr(keys, function(k) {
  load(file.path(rb, "04-data/04-test-data", paste0(k, ".RData")))
  load(file.path(rb, "04-data/03-train-data", paste0(k, ".RData")))
  p <- strsplit(k, "_")[[1]]
  te <- d_test %>% select(Full_Date) %>%
    left_join(filter(labels, SID == p[1], outcome == p[2]), by = "Full_Date")
  y <- te$o_value; ytr <- as.numeric(as.character(d_train$o_value))
  tibble(SID = p[1], outcome = p[2], group = p[3], set = p[4], time = p[5],
         n_test = length(y), test_pos = sum(y),
         maj_test = max(mean(y), 1 - mean(y)),
         maj_train = mean(y == as.numeric(mean(ytr) > .5)),
         persist_auc = auc1(y, te$current), persist_acc = mean(y == te$current))
})

read_res <- function(m) {
  r <- bind_rows(lapply(list.files(file.path(dir, m), pattern = "rds$", full.names = TRUE), readRDS))
  auc_metric <- if (m == "biscwit") "roc_auc_event1" else "roc_auc"
  r %>% filter(.metric %in% c("accuracy", auc_metric)) %>%
    mutate(.metric = ifelse(.metric == "accuracy", "acc", "auc")) %>%
    select(SID, outcome, group, set, time, .metric, .estimate) %>%
    pivot_wider(names_from = .metric, values_from = .estimate) %>%
    mutate(model = m)
}
res <- bind_rows(lapply(intersect(c("glmnet", "biscwit", "rf"), list.files(dir)), read_res)) %>%
  inner_join(bench, by = c("SID", "outcome", "group", "set", "time"))
write.csv(res, file.path(dir, "corrected_model_results.csv"), row.names = FALSE)

cat("== Per model split ==\n")
res %>% group_by(model, outcome) %>%
  summarize(splits = n(), acc_na = sum(is.na(acc)), acc = mean(acc, na.rm = TRUE), maj_test = mean(maj_test), maj_train = mean(maj_train),
            beats_maj_test = mean(acc > maj_test, na.rm = TRUE), auc_defined = sum(!is.na(auc)),
            auc = mean(auc, na.rm = TRUE), persist_auc = mean(persist_auc[!is.na(auc)], na.rm = TRUE),
            .groups = "drop") %>%
  as.data.frame() %>% print(digits = 3)

ttest <- function(x, mu = .5) {
  x <- x[!is.na(x)]; if (length(x) < 3) return(c(mean = mean(x), lo = NA, hi = NA, p = NA))
  t <- t.test(x, mu = mu); c(mean = mean(x), lo = t$conf.int[1], hi = t$conf.int[2], p = t$p.value) }
person <- function(d, label) {
  d %>% filter(!is.na(auc)) %>%
    group_by(model, outcome, SID) %>%
    summarize(auc = mean(auc), persist = mean(persist_auc, na.rm = TRUE), .groups = "drop") %>%
    group_by(model, outcome) %>%
    summarize(subset = label, N = n(),
              vs_chance = list(ttest(auc)),
              persist = mean(persist, na.rm = TRUE),
              diff_vs_persist = list(ttest(auc - persist, 0)), .groups = "drop") %>%
    unnest_wider(vs_chance, names_sep = "_") %>% unnest_wider(diff_vs_persist, names_sep = "_")
}
pl <- bind_rows(person(res, "all 14 feature sets"),
                person(filter(res, group == "full", time == "time"), "full + time (pre-specified)"))
cat("\n== Person-level AUC (mean over each person's feature sets) ==\n")
pl %>% mutate(across(where(is.double), ~ signif(.x, 3))) %>% as.data.frame() %>% print()
write.csv(pl, file.path(dir, "corrected_person_level.csv"), row.names = FALSE)

cat("\n== Persistence benchmark alone (person level, all splits with defined AUC) ==\n")
bench %>% filter(!is.na(persist_auc)) %>% group_by(outcome, SID) %>%
  summarize(a = mean(persist_auc), .groups = "drop") %>% group_by(outcome) %>%
  summarize(N = n(), mean = mean(a), lo = t.test(a, mu = .5)$conf.int[1], hi = t.test(a, mu = .5)$conf.int[2],
            p = t.test(a, mu = .5)$p.value) %>% as.data.frame() %>% print(digits = 3)

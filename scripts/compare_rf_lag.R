# Does RF's above-chance AUC come from the lagged outcome (o_value_2)?
# Compares RF full / no_lag / lag_only on identical test sets. The 14 feature
# sets per participant share one test window, so tests average within person
# first and treat participants as the unit.
# Usage: Rscript scripts/compare_rf_lag.R <derived_dir>
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
dir <- commandArgs(trailingOnly = TRUE)[1]
keys <- c("SID", "outcome", "group", "set", "time")
read_mode <- function(m, sub) bind_rows(lapply(list.files(file.path(dir, sub), pattern = "rds$", full.names = TRUE), readRDS)) %>%
  filter(.metric %in% c("accuracy", "roc_auc")) %>% transmute(across(all_of(keys)), .metric, mode = m, est = .estimate)
d <- bind_rows(read_mode("full", "rf"), read_mode("no_lag", "rf_no_lag"), read_mode("lag_only", "rf_lag_only")) %>%
  pivot_wider(names_from = mode, values_from = est) %>%
  filter(!is.na(full), !is.na(no_lag), !is.na(lag_only))

cat("Models with all three variants:", n_distinct(paste(d$SID, d$outcome, d$group, d$set, d$time)), "\n\n")
cat("Mean over models:\n")
d %>% group_by(outcome, .metric) %>%
  # comparisons first: summarize() would otherwise see the already-averaged columns
  summarize(n = n(), full_gt_nolag = mean(full > no_lag + 1e-9), full_lt_nolag = mean(full < no_lag - 1e-9),
            full = mean(full), no_lag = mean(no_lag), lag_only = mean(lag_only), .groups = "drop") %>%
  as.data.frame() %>% print(digits = 3)

# person-level: average each variant's AUC within participant, then test
p <- d %>% filter(.metric == "roc_auc") %>%
  group_by(SID, outcome) %>% summarize(across(c(full, no_lag, lag_only), mean), .groups = "drop")
cat("\nPerson-level AUC (mean of each person's 14 feature sets):\n")
for (o in unique(p$outcome)) {
  q <- filter(p, outcome == o)
  t1 <- function(x) { tt <- t.test(x, mu = .5); sprintf("%.3f [%.3f, %.3f] p=%.3g", mean(x), tt$conf.int[1], tt$conf.int[2], tt$p.value) }
  tp <- t.test(q$full, q$no_lag, paired = TRUE)
  cat(sprintf("  %s (N = %d people)\n    vs .5: full %s\n           no_lag %s\n           lag_only %s\n    full - no_lag: %.3f [%.3f, %.3f] p=%.3g\n",
              o, nrow(q), t1(q$full), t1(q$no_lag), t1(q$lag_only),
              mean(q$full - q$no_lag), tp$conf.int[1], tp$conf.int[2], tp$p.value))
}
write.csv(d, file.path(dir, "rf_lag_comparison.csv"), row.names = FALSE)

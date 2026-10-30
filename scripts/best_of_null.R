# How good does the paper's "best model" summary look when predictions are noise?
# 05-summary.Rmd picks, per participant x outcome, the feature set (set == "all":
# psych / situations / full, each with and without time) with the highest TEST
# metric, excluding estimates of exactly 1. Here each candidate's test predictions
# are replaced by random scores, using every participant's real test-set outcomes.
# The null uses the shipped test sets (glmnet/BISCWIT); RF's own split is the same
# rows minus the first (lag embedding), so the null is shared across methods.
# Usage: Rscript scripts/best_of_null.R <repo> <published RData> <rerun_dir> [n_sims] [model]
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(purrr); library(rsample)})
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; n_sims <- if (length(args) >= 4) as.integer(args[4]) else 200
model_name <- if (length(args) >= 5) args[5] else "glmnet"
set.seed(2026)

load(args[2])  # sum_res
pub <- unnest(sum_res, data) %>% filter(model == model_name, outcome %in% c("lonely", "prcrst"))
rerun <- bind_rows(lapply(list.files(args[3], pattern = "rds$", full.names = TRUE), readRDS))

# the paper's selection rule
best_of <- function(d, est) d %>%
  filter(set == "all", .metric == "roc_auc", !is.na({{ est }}), {{ est }} != 1) %>%
  group_by(SID, outcome) %>% summarize(best = max({{ est }}), .groups = "drop")

# real test-set outcomes for every candidate model
cands <- tibble(file = list.files(sprintf("%s/04-data/04-test-data", repo))) %>%
  mutate(key = sub("\\.RData$", "", file)) %>%
  separate(key, c("SID", "outcome", "group", "set", "time"), sep = "_", remove = FALSE) %>%
  filter(set == "all")
cands$y <- map(cands$file, function(f) {
  load(sprintf("%s/04-data/04-test-data/%s", repo, f))
  as.integer(as.character(testing(d_split)$o_value))
})

auc <- function(y, s) {  # Mann-Whitney AUC; NA if a class is missing (as yardstick)
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(s); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
null_best <- map_dfr(seq_len(n_sims), function(i) {
  cands %>%
    mutate(.metric = "roc_auc", null = map_dbl(y, ~ auc(.x, runif(length(.x))))) %>%
    best_of(null) %>% group_by(outcome) %>%
    summarize(mean = mean(best), median = median(best), share_gt_.7 = mean(best > .7), .groups = "drop") %>%
    mutate(sim = i)
})

summ <- function(d, label) d %>% group_by(outcome) %>%
  summarize(source = label, N = n(), mean = mean(best), median = median(best),
            share_gt_.7 = mean(best > .7), .groups = "drop")
out <- bind_rows(
  summ(best_of(pub, .estimate), "published"),
  summ(best_of(rerun, .estimate), "rerun"),
  null_best %>% group_by(outcome) %>%
    summarize(source = sprintf("random scores (%d sims)", n_sims), N = NA,
              mean = mean(mean), median = mean(median), share_gt_.7 = mean(share_gt_.7), .groups = "drop")
) %>% arrange(outcome, source)
cat(sprintf("Best-of-6 test AUC per participant, %s (the paper's Figure 1 summary):\n", model_name))
print(as.data.frame(out), digits = 3)
cat("\nTest-set size per candidate: median", median(lengths(cands$y)),
    "| positives median", median(map_int(cands$y, sum)), "\n")
write.csv(out, file.path(args[3], "..", paste0(model_name, "_best_of_null.csv")), row.names = FALSE)

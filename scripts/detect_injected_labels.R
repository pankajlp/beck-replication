# save_fun (01-data-cleaning.Rmd) applies test_fun to dummy_vars, which include
# the outcome o_value: if a test set has one class, a random test label is flipped
# to the other class (train_fun does similar in training). Detect flipped labels by
# comparing shipped outcomes with the next-beep outcome rebuilt from raw data.
# data_fun takes lead() in all_features' row order, which sorts Full_Date as text;
# hours are not zero-padded ("8:44" sorts after "21:00"), so "next beep" can be an
# earlier beep. true_o follows their (text) order, to isolate injected labels;
# time_o follows clock order, to count mis-ordered targets.
# Usage: Rscript scripts/detect_injected_labels.R <repo> <all_features.RData> <out_csv>
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(purrr); library(rsample)})
args <- commandArgs(trailingOnly = TRUE); repo <- args[1]
load(args[2])  # all_features
base_rows <- all_features %>%
  filter(trait %in% c("lonely", "prcrst")) %>%
  select(SID, outcome = trait, Full_Date, value) %>% distinct()
truth <- base_rows %>%
  arrange(SID, outcome, Full_Date) %>%
  group_by(SID, outcome) %>% mutate(true_o = lead(value)) %>% ungroup() %>%
  left_join(base_rows %>%
              arrange(SID, outcome, lubridate::ymd_hm(Full_Date)) %>%
              group_by(SID, outcome) %>% mutate(time_o = lead(value), time_next = lead(Full_Date)) %>% ungroup() %>%
              select(-value), by = c("SID", "outcome", "Full_Date")) %>%
  select(-value)

keys <- tibble(key = sub("\\.RData$", "", list.files(sprintf("%s/04-data/04-test-data", repo)))) %>%
  separate(key, c("SID", "outcome", "group", "set", "time"), sep = "_", remove = FALSE)
check <- function(part, sid, oc, key) {
  if (part == "test") { load(sprintf("%s/04-data/04-test-data/%s.RData", repo, key)); d <- testing(d_split) }
  else { load(sprintf("%s/04-data/03-train-data/%s.RData", repo, key)); d <- d_train }
  d %>% transmute(Full_Date, o = as.numeric(as.character(o_value))) %>%
    left_join(filter(truth, SID == sid, outcome == oc), by = "Full_Date") %>%
    summarize(n = n(), matched = sum(!is.na(true_o)), flipped = sum(o != true_o, na.rm = TRUE),
              true_one_class = n_distinct(true_o, na.rm = TRUE) == 1,
              misordered = sum(!is.na(true_o) & (is.na(time_o) | true_o != time_o)))
}
res <- keys %>%
  mutate(test = pmap(list(SID, outcome, key), ~ check("test", ..1, ..2, ..3)),
         train = pmap(list(SID, outcome, key), ~ check("train", ..1, ..2, ..3))) %>%
  unnest(c(test, train), names_sep = "_")

cat("Label check against raw-data outcomes (", nrow(res), "model splits)\n")
cat(sprintf("  test rows matched to raw data: %.1f%%\n", 100 * sum(res$test_matched) / sum(res$test_n)))
cat(sprintf("  test sets with >= 1 flipped label: %d (%.1f%%)\n", sum(res$test_flipped > 0), 100 * mean(res$test_flipped > 0)))
cat(sprintf("  ... whose true test outcome was a single class: %d\n", sum(res$test_flipped > 0 & res$test_true_one_class)))
cat(sprintf("  train sets with >= 1 flipped label: %d (%.1f%%)\n", sum(res$train_flipped > 0), 100 * mean(res$train_flipped > 0)))
cat(sprintf("  test labels whose value differs from the clock-order next beep: %.1f%%\n",
            100 * sum(res$test_misordered) / sum(res$test_matched)))
res %>% group_by(outcome) %>%
  summarize(splits = n(), test_flipped = mean(test_flipped > 0), train_flipped = mean(train_flipped > 0),
            test_misordered_labels = sum(test_misordered) / sum(test_matched)) %>%
  as.data.frame() %>% print(digits = 3)
write.csv(select(res, SID, outcome, group, set, time, starts_with("test_"), starts_with("train_")), args[3], row.names = FALSE)

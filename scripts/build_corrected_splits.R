# Rebuild the per-person train/test files (01-data-cleaning.Rmd, data_fun/save_fun)
# from derived/all_features.RData with the label and timing bugs fixed:
#   - Full_Date is zero-padded ("2018-10-24 08:44"), so text order = clock order and
#     the unchanged runners' arrange(Full_Date) is correct
#   - o_value is the outcome at the NEXT observed beep in clock order (as the paper
#     describes), not the previous beep
#   - no label injection: one-class test sets are kept as they are (AUC undefined)
#   - feature dummies are not altered either; features constant in training are
#     dropped (decided on training rows only)
#   - time features: night = Hour >= 22 | Hour < 5, evening = 17-22, and the trend
#     is days since first beep (no scaling across people or across the split)
# Kept as in the original: feature sets, complete cases, >= 40 rows per person,
# 75/25 time split, training needs >= 2 of each class, Amelia-imputed BFI-2.
# Writes <out>/04-data/{02-model-data,03-train-data,04-test-data} in the shipped
# format, plus <out>/labels.csv (current and next outcome per row, for baselines)
# and <out>/splits.csv (one row per model split).
# Usage: Rscript scripts/build_corrected_splits.R <all_features.RData> <out>
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr); library(rsample); library(lubridate)
})
args <- commandArgs(trailingOnly = TRUE)
load(args[1])  # all_features, ipcs_times
out_root <- args[2]
for (s in c("02-model-data", "03-train-data", "04-test-data"))
  dir.create(file.path(out_root, "04-data", s), recursive = TRUE, showWarnings = FALSE)

pad <- function(x) format(ymd_hm(x), "%Y-%m-%d %H:%M")
stopifnot(!anyNA(pad(na.omit(all_features$Full_Date))))

time_features <- ipcs_times %>%
  mutate(Full_Date = pad(Full_Date)) %>%
  mutate(wkday = wday(ymd_hm(Full_Date), label = TRUE, locale = "C")
         , Mon =     ifelse(wkday == "Mon", 1, 0)
         , Tue =     ifelse(wkday == "Tue", 1, 0)
         , Wed =     ifelse(wkday == "Wed", 1, 0)
         , Thu =     ifelse(wkday == "Thu", 1, 0)
         , Fri =     ifelse(wkday == "Fri", 1, 0)
         , Sat =     ifelse(wkday == "Sat", 1, 0)
         , Sun =     ifelse(wkday == "Sun", 1, 0)
         , morning = ifelse(Hour >= 5  & Hour < 11, 1, 0)
         , midday =  ifelse(Hour >= 11 & Hour < 17, 1, 0)
         , evening = ifelse(Hour >= 17 & Hour < 22, 1, 0)
         , night =   ifelse(Hour >= 22 | Hour < 5,  1, 0)) %>%
  arrange(SID, Full_Date) %>%
  group_by(SID) %>%
  mutate(tdif = as.numeric(difftime(ymd_hm(Full_Date), lag(ymd_hm(Full_Date)), units = "hours"))) %>%
  filter(is.na(tdif) | tdif > 1) %>%
  mutate(tdif = as.numeric(difftime(ymd_hm(Full_Date), lag(ymd_hm(Full_Date)), units = "hours")),
         tdif = ifelse(is.na(tdif), 0, tdif),
         cumsumT = cumsum(tdif)) %>%
  ungroup() %>%
  mutate(linear = cumsumT / 24, quad = linear^2, cub = linear^3,
         sin1p = sin(((2*pi)/24)*cumsumT), sin2p = sin(((2*pi)/12)*cumsumT),
         cos1p = cos(((2*pi)/24)*cumsumT), cos2p = cos(((2*pi)/12)*cumsumT)) %>%
  select(SID, Full_Date, Mon:night, linear:cos2p) %>%
  pivot_longer(c(-SID, -Full_Date), names_to = "trait", values_to = "value") %>%
  mutate(category = "time", facet = trait)

af <- all_features %>%
  filter(is.na(category) | category != "time") %>%
  mutate(Full_Date = pad(Full_Date)) %>%
  bind_rows(time_features)

dummy_vars <- c("o_value", "argument", "interacted", "lostSmthng", "late", "frgtSmthng",
                "brdSWk", "excSWk", "AnxSWk", "tired", "sick", "sleeping", "class",
                "music", "internet", "TV", "study", "prcrst", "lonely")
time_dummy <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "morning", "midday", "evening", "night")

save_fun <- function(d, group, set, outcome, SID, time) {
  key <- paste(SID, outcome, group, set, time, sep = "_")
  d <- arrange(d, Full_Date)
  n_tr <- floor(nrow(d) * 0.75)  # initial_time_split's training size
  o_tr <- d$o_value[seq_len(n_tr)]
  info <- tibble(key = key, n = nrow(d), n_train = n_tr, train_pos = sum(o_tr == 1),
                 test_pos = sum(d$o_value[-seq_len(n_tr)] == 1), kept = FALSE)
  if (min(sum(o_tr == 1), sum(o_tr == 0)) < 2) return(info)
  # drop features constant in training (training rows only decide)
  feats <- setdiff(names(d), c("Full_Date", "o_value"))
  const <- feats[map_lgl(feats, ~ n_distinct(d[[.x]][seq_len(n_tr)]) < 2)]
  d <- d %>% select(-all_of(const)) %>%
    mutate(across(any_of(c(dummy_vars, time_dummy)), ~ factor(.x, levels = c(0, 1))))
  d_split <- initial_time_split(d, prop = 0.75)
  d_train <- training(d_split); d_test <- testing(d_split)
  stopifnot(nrow(d_train) == n_tr)
  save(d, file = sprintf("%s/04-data/02-model-data/%s.RData", out_root, key))
  save(d_train, file = sprintf("%s/04-data/03-train-data/%s.RData", out_root, key))
  save(d_test, d_split, file = sprintf("%s/04-data/04-test-data/%s.RData", out_root, key))
  mutate(info, kept = TRUE, dropped_const = length(const))
}

outcome_series <- function(outcome) {
  s <- af %>% filter(trait == outcome) %>% select(SID, Full_Date, value) %>% distinct()
  stopifnot(!anyDuplicated(s[c("SID", "Full_Date")]))
  s %>% arrange(SID, Full_Date) %>% group_by(SID) %>%
    mutate(o_value = lead(value), next_date = lead(Full_Date)) %>% ungroup()
}

data_fun <- function(group, set, outcome, time) {
  if (set != "all") groups <- set
  if (set == "all") {
    if (group == "psychological") groups <- c("BFI-2", "Affect")
    else if (group == "situations") groups <- c("S8-I", "sit")
    else groups <- c("BFI-2", "Affect", "S8-I", "sit")
  }
  if (time == "time") groups <- c(groups, "time")
  out <- outcome_series(outcome) %>% select(SID, Full_Date, o_value)
  d <- af %>%
    filter(category %in% groups & trait != outcome) %>%
    mutate(name = ifelse(category == "BFI-2", paste(trait, facet, sep = "_"), trait)) %>%
    select(SID, Full_Date, name, value) %>%
    distinct() %>%
    pivot_wider(names_from = "name", values_from = "value") %>%
    inner_join(out, by = c("SID", "Full_Date")) %>%
    filter(complete.cases(.))
  d %>% group_by(SID) %>% filter(n() >= 40) %>% nest() %>% ungroup() %>%
    mutate(info = map2(data, SID, ~ save_fun(.x, group, set, outcome, .y, time))) %>%
    select(info) %>% unnest(info)
}

nested <- tribble(
  ~group, ~set,
  "psychological", "BFI-2",
  "psychological", "Affect",
  "psychological", "all",
  "situations", "sit",
  "situations", "S8-I",
  "situations", "all",
  "full", "all") %>%
  crossing(time = c("no time", "time"), outcome = c("lonely", "prcrst"))
splits <- pmap_dfr(nested, data_fun)
write.csv(splits, file.path(out_root, "splits.csv"), row.names = FALSE)

labels <- bind_rows(lapply(c("lonely", "prcrst"), function(o) mutate(outcome_series(o), outcome = o))) %>%
  rename(current = value)
write.csv(labels, file.path(out_root, "labels.csv"), row.names = FALSE)

cat(sprintf("splits considered: %d, kept: %d (people: %d)\n", nrow(splits), sum(splits$kept),
            n_distinct(str_extract(splits$key[splits$kept], "^[^_]+"))))
k <- filter(splits, kept)
cat(sprintf("kept test sets with one outcome class: %d (%.1f%%)\n",
            sum(k$test_pos == 0 | k$test_pos == k$n - k$n_train),
            100 * mean(k$test_pos == 0 | k$test_pos == k$n - k$n_train)))
gap <- labels %>% filter(!is.na(next_date)) %>%
  mutate(h = as.numeric(difftime(ymd_hm(next_date), ymd_hm(Full_Date), units = "hours")))
cat(sprintf("hours to the next observed beep: median %.1f, > 12 h: %.1f%%, <= 0: %d\n",
            median(gap$h), 100 * mean(gap$h > 12), sum(gap$h <= 0)))

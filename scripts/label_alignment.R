# Which rebuilt series do the shipped outcome labels (o_value) follow? Also checks
# a shipped feature against the rebuilt data, to tell whether the shipped splits
# come from the same cleaned data as the shipped raw files.
# Usage: Rscript scripts/label_alignment.R <repo> <all_features.RData>
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(purrr); library(rsample)})
args <- commandArgs(trailingOnly = TRUE); repo <- args[1]
load(args[2])
rows <- all_features %>% filter(trait %in% c("lonely", "prcrst")) %>%
  select(SID, outcome = trait, Full_Date, value) %>% distinct()
cand <- rows %>%
  arrange(SID, outcome, Full_Date) %>% group_by(SID, outcome) %>%
  mutate(lead_text = lead(value), lag_text = lag(value)) %>%
  arrange(SID, outcome, lubridate::ymd_hm(Full_Date)) %>%
  mutate(lead_time = lead(value), lag_time = lag(value)) %>% ungroup() %>%
  rename(same_beep = value)

# one feature set per participant x outcome is enough (labels are shared)
keys <- tibble(key = sub("\\.RData$", "", list.files(sprintf("%s/04-data/02-model-data", repo)))) %>%
  separate(key, c("SID", "outcome", "group", "set", "time"), sep = "_", remove = FALSE) %>%
  filter(group == "psychological", set == "Affect", time == "no time")
shipped <- pmap_dfr(keys, function(key, SID, outcome, ...) {
  load(sprintf("%s/04-data/02-model-data/%s.RData", repo, key))
  tibble(SID = SID, outcome = outcome, Full_Date = d$Full_Date,
         o = as.numeric(as.character(d$o_value)), happy = d$happy)
})
j <- inner_join(shipped, cand, by = c("SID", "outcome", "Full_Date"))
cat(sprintf("shipped rows: %d, matched to rebuilt timestamps: %d\n", nrow(shipped), nrow(j)))
cat("Agreement of shipped o_value with each candidate:\n")
for (v in c("same_beep", "lead_text", "lead_time", "lag_text", "lag_time"))
  cat(sprintf("  %-10s %.3f\n", v, mean(j$o == j[[v]], na.rm = TRUE)))

feat <- all_features %>% filter(trait == "happy") %>% select(SID, Full_Date, happy_rebuilt = value) %>% distinct()
k <- inner_join(shipped, feat, by = c("SID", "Full_Date"))
cat(sprintf("\nFeature check (happy): %d rows matched, identical values: %.3f\n",
            nrow(k), mean(abs(k$happy - k$happy_rebuilt) < 1e-9, na.rm = TRUE)))

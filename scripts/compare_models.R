# Compare re-run test metrics with the published per-model results.
# Usage: Rscript scripts/compare_glmnet.R <rerun_dir> <published RData> [--detail] [--model=glmnet|biscwit|rf]
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
args <- commandArgs(trailingOnly = TRUE)
model_name <- sub("--model=", "", c(grep("^--model=", args, value = TRUE), "--model=glmnet")[1])
load(args[2])  # sum_res
pub <- unnest(sum_res, data) %>%
  filter(model == model_name, outcome %in% c("lonely", "prcrst")) %>%
  select(SID, outcome, group, set, time, .metric, published = .estimate)
mine <- bind_rows(lapply(list.files(args[1], pattern = "rds$", full.names = TRUE), readRDS)) %>%
  filter(.metric %in% c("accuracy", "roc_auc")) %>%
  rename(rerun = .estimate)
keys <- c("SID", "outcome", "group", "set", "time", ".metric")
cmp <- full_join(mine, pub, by = keys) %>%
  mutate(diff = rerun - published, exact = abs(diff) < 1e-6)

if ("--detail" %in% args) print(as.data.frame(select(cmp, all_of(keys), rerun, published, any_of(c("penalty", "mixture", "nitem", "cv_r", "mtry", "min_n")))))

cat("\nModels: rerun", n_distinct(paste(mine$SID, mine$outcome, mine$group, mine$set, mine$time)),
    "| published", n_distinct(paste(pub$SID, pub$outcome, pub$group, pub$set, pub$time)), "\n")
both <- filter(cmp, !is.na(rerun), !is.na(published))
cat("\nAgreement on models present in both:\n")
both %>% group_by(outcome, .metric) %>%
  summarize(n = n(), exact = mean(exact), r = cor(rerun, published, use = "complete.obs"),
            mean_rerun = mean(rerun, na.rm = TRUE), mean_pub = mean(published, na.rm = TRUE),
            mean_abs_diff = mean(abs(diff), na.rm = TRUE), .groups = "drop") %>%
  as.data.frame() %>% print(digits = 3)
cat("\nOnly in rerun:", sum(is.na(cmp$published) & !is.na(cmp$rerun)),
    "| only in published:", sum(is.na(cmp$rerun) & !is.na(cmp$published)), "rows\n")

# the paper's headline numbers: mean test AUC/accuracy by feature set
cat("\nMean test metric by feature set (rerun vs published):\n")
both %>% group_by(outcome, .metric, group, set, time) %>%
  summarize(rerun = mean(rerun, na.rm = TRUE), published = mean(published, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = .metric, values_from = c(rerun, published)) %>%
  as.data.frame() %>% print(digits = 3)
write.csv(cmp, file.path(args[1], "..", paste0(model_name, "_comparison.csv")), row.names = FALSE)

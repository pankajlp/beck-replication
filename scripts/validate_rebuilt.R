# Compare rebuilt splits with the shipped ones: same keys, rows and feature values;
# rebuilt labels = clock-order next beep. Usage: Rscript validate_rebuilt.R <repo> <rebuilt>
suppressPackageStartupMessages({library(dplyr); library(purrr); library(lubridate)})
a <- commandArgs(TRUE); sh <- file.path(a[1], "04-data/02-model-data"); rb <- file.path(a[2], "04-data/02-model-data")
ks <- sub("\\.RData$", "", list.files(sh)); kr <- sub("\\.RData$", "", list.files(rb))
cat(sprintf("shipped %d, rebuilt %d, both %d\n", length(ks), length(kr), length(intersect(ks, kr))))
ld <- function(p) { load(p); d %>% mutate(Full_Date = format(ymd_hm(Full_Date), "%Y-%m-%d %H:%M")) }
labs <- read.csv(file.path(a[2], "labels.csv"), colClasses = c(SID = "character"))
res <- map_dfr(intersect(ks, kr), function(k) {
  s <- ld(file.path(sh, paste0(k, ".RData"))); r <- ld(file.path(rb, paste0(k, ".RData")))
  j <- inner_join(s, r, by = "Full_Date", suffix = c(".s", ".r"))
  f <- intersect(setdiff(names(s), c("Full_Date", "o_value")), names(r))
  same <- if (length(f)) mean(map_dbl(f, ~ mean(as.character(j[[paste0(.x, ".s")]]) == as.character(j[[paste0(.x, ".r")]])))) else NA
  p <- strsplit(k, "_")[[1]]
  l <- filter(labs, SID == p[1], outcome == p[2]) %>% inner_join(r, by = "Full_Date")
  tibble(key = k, n_s = nrow(s), n_r = nrow(r), shared_rows = nrow(j), feat_same = same,
         label_is_next = mean(as.character(l$o_value.x) == as.character(l$o_value.y)),
         label_same_as_shipped = mean(as.character(j$o_value.s) == as.character(j$o_value.r)))
})
print(summary(select(res, -key)))

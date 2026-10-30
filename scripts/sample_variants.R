# Explore which sample definition yields the published N = 104 / 5,971.
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(tibble)})
args <- commandArgs(trailingOnly = TRUE)
load(args[1])  # derived/all_features.RData
repo <- args[2]
shipped <- tibble(f = list.files(sprintf("%s/04-data/02-model-data", repo))) %>%
  separate(f, c("SID", "outcome"), sep = "_", extra = "drop")
counts <- function(cats) all_features %>%
  filter(category %in% cats) %>%
  group_by(SID, Full_Date, trait, facet, category) %>% summarize(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = c(category, trait, facet), values_from = value) %>%
  filter(complete.cases(.)) %>% count(SID)
show <- function(label, d) cat(sprintf("%-60s N = %3d, assessments = %5d\n", label, nrow(d), sum(d$n)))
as_written <- counts(c("Affect", "BFI-2", "sit", "SI-8"))   # their code ("SI-8" matches nothing)
with_s8    <- counts(c("Affect", "BFI-2", "sit", "S8-I"))   # DIAMONDS actually included
show("shipped SIDs, no >=40 cut, code as written", filter(as_written, SID %in% shipped$SID))
show("shipped SIDs, >=40, code as written", filter(as_written, SID %in% shipped$SID, n >= 40))
show("shipped SIDs, no >=40 cut, with DIAMONDS", filter(with_s8, SID %in% shipped$SID))
show(">=40 with DIAMONDS", filter(with_s8, n >= 40))
show("shipped SIDs, >=40 with DIAMONDS", filter(with_s8, SID %in% shipped$SID, n >= 40))
cat("shipped SIDs missing from complete-case counts:",
    setdiff(unique(shipped$SID), as_written$SID), "\n")

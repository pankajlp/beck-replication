# Run Beck & Jackson's 01-data-cleaning.Rmd offline against the local clone and
# reproduce the published sample (N = 104; 5,971 assessments).
# Usage: Rscript scripts/run_cleaning.R <path to behavior-prediction clone>

args <- commandArgs(trailingOnly = TRUE)
repo <- normalizePath(args[1])
script_dir <- dirname(normalizePath(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))))

suppressPackageStartupMessages({
  library(psych)
  library(Amelia)
  library(lubridate)
  library(plyr)
  # tidyverse meta-package needs system font libs; load its components directly
  for (p in c("ggplot2", "tibble", "tidyr", "readr", "purrr", "dplyr", "stringr", "forcats")) library(p, character.only = TRUE)
  library(rsample)
})

# the authors' path variables, pointed at the local clone
res_path <- repo
local_path <- repo

ipcs_codebook <- readxl::read_xlsx(sprintf("%s/01-codebooks/codebook_R1.xlsx", repo), sheet = "codebook")

# extract the R chunks from the Rmd, skipping eval = F chunks
rmd <- readLines(sprintf("%s/03-scripts/02-revision/01-data-cleaning.Rmd", repo))
starts <- grep("^```\\{r", rmd)
ends <- grep("^```\\s*$", rmd)
chunks <- lapply(starts, function(s) {
  e <- min(ends[ends > s])
  list(header = rmd[s], code = rmd[(s + 1):(e - 1)])
})
chunks <- Filter(function(ch) !grepl("eval\\s*=\\s*F", ch$header), chunks)
# the final chunk wipes the workspace; keep the objects for checking
chunks <- Filter(function(ch) !any(grepl("rm(list = ls()", ch$code, fixed = TRUE)), chunks)

# the demographics chunk lists the glmnet tuning-model folder, which we did not
# clone (4 GB); use the filename listing fetched from the GitHub API instead
tuning_files <- readLines(file.path(script_dir, "glmnet_tuning_files.txt"))

code <- unlist(lapply(chunks, `[[`, "code"))
code <- gsub("load(url(", "load((", code, fixed = TRUE)
code <- gsub('list.files(sprintf("%s/05-results/01-glmnet/01-tuning-models", res_path))',
             "tuning_files", code, fixed = TRUE)
code <- gsub('list.files(sprintf("%s/05-results/01-glmnet/01-tuning-models", local_path))',
             "tuning_files", code, fixed = TRUE)

set.seed(5)
exprs <- parse(text = code)
for (i in seq_along(exprs)) {
  out <- withVisible(eval(exprs[[i]], envir = globalenv()))
  # print only the summaries the Rmd displays at the end (demographics)
  if (out$visible && is.data.frame(out$value) && "N" %in% names(out$value)) {
    print(as.data.frame(out$value))
  }
}

# candidate definitions of the paper's headline sample
tuned <- tibble(f = tuning_files) %>% separate(f, c("SID", "outcome"), sep = "_", extra = "drop")
shipped <- tibble(f = list.files(sprintf("%s/04-data/02-model-data", repo))) %>%
  separate(f, c("SID", "outcome"), sep = "_", extra = "drop")
report <- function(label, sids) {
  d <- final_dem %>% filter(SID %in% sids)
  cat(sprintf("%-55s N = %3d, assessments = %5d\n", label, n_distinct(d$SID), sum(d$n)))
}
cat("\nPublished:                                              N = 104, assessments =  5971\n")
report(">=40 complete surveys (all)", final_dem$SID)
report("... with glmnet tuning model, any of 7 outcomes", tuned$SID)
report("... with glmnet tuning model, lonely or prcrst", tuned$SID[tuned$outcome %in% c("lonely", "prcrst")])
report("... in shipped 02-model-data (lonely/prcrst)", shipped$SID)

save(all_features, ipcs_times, final_dem, file = file.path(dirname(script_dir), "derived", "all_features.RData"))

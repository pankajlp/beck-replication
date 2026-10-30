#!/bin/zsh
# Run all three methods on the rebuilt (corrected) splits.
cd "$(dirname $0)/.."
export R_LIBS_USER=$PWD/Rlib
Rscript scripts/run_biscwit.R rebuilt derived/corrected/biscwit 16 --fixed > derived/corrected/biscwit_run.log 2>&1
Rscript scripts/run_rf.R rebuilt derived/corrected/rf 16 --fixed > derived/corrected/rf_run.log 2>&1
Rscript scripts/run_glmnet.R rebuilt derived/corrected/glmnet 16 > derived/corrected/glmnet_run.log 2>&1
grep -h "done in" derived/corrected/*_run.log

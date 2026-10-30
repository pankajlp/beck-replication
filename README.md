# Replication of Beck & Jackson (2022)

A replication and correction of:

> Beck, E. D., & Jackson, J. J. (2022). Personalized prediction of behaviors and experiences: An idiographic person–situation test. *Psychological Science*, *33*(10), 1767–1782. https://doi.org/10.1177/09567976221093307

## What this is

The original paper reported that idiographic machine-learning models could predict next-survey loneliness and procrastination from experience-sampling data. This replication found three data-processing issues that reversed the prediction direction: models were predicting the previous survey's outcome, not the next. After correction, no method exceeds persistence or chance.

See `STEP1_FINDINGS.md` for the full analysis with all numbers, and `MANUSCRIPT.md` for the write-up.

## Setup

You need the original repo's data:

```bash
git clone --filter=blob:none --sparse https://github.com/emoriebeck/behavior-prediction upstream/behavior-prediction
cd upstream/behavior-prediction
git sparse-checkout set 04-data 03-scripts derived
```

R 4.6.1 via Homebrew with a project library:

```bash
R_LIBS_USER=$PWD/Rlib Rscript -e 'install.packages(c("dplyr","tidyr","purrr","stringr","rsample","lubridate","glmnet","ranger","yardstick","furrr","psych"), lib="Rlib")'
```

## Scripts

| Script | What it does |
|--------|-------------|
| `label_alignment.R` | Compares shipped o_value against rebuilt outcome series |
| `detect_injected_labels.R` | Identifies test sets with modified labels |
| `build_corrected_splits.R` | Rebuilds 1,870 splits with corrected labels |
| `run_glmnet.R` | Elastic net runner (resumable) |
| `run_biscwit.R` | BISCWIT runner (resumable, `--fixed` for signed r) |
| `run_rf.R` | Random forest runner (resumable, `--fixed` for log safety) |
| `run_pooled.R` | Pooled person-mean-centered glmnet |
| `corrected_summary.R` | Three-method summary with benchmarks |
| `validate_rebuilt.R` | Compares rebuilt splits against shipped |

All R scripts run as `R_LIBS_USER=$PWD/Rlib Rscript scripts/<name>.R <args>`. Python scripts run as `.venv/bin/python -I scripts/<name>.py`.

## Key result

With corrected labels (next beep in clock order, no label injection):

| Method | Loneliness AUC (p) | Procrastination AUC (p) |
|--------|-------------------|------------------------|
| BISCWIT | .561 (.029) | .504 (.827) |
| Elastic net | .541 (.126) | .498 (.925) |
| Random forest | .531 (.277) | .516 (.360) |
| Pooled glmnet | .507 (.477) | .522 (.012) |
| Persistence | .547 (.066) | .514 (.369) |

No method beats persistence for either outcome.

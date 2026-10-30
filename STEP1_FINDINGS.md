# Step 1 — Beck & Jackson (2022) data & code inspection

Paper: Beck, E. D., & Jackson, J. J. (2022). *Personalized Prediction of Behaviors and Experiences: An Idiographic Person–Situation Test.* Psychological Science. doi:10.1177/09567976221093307
Code + data: https://github.com/emoriebeck/behavior-prediction (cloned to `upstream/behavior-prediction`, excluding the ~4 GB `05-results/` folder)

## Sample funnel (reproduced by `scripts/count_sample.py`)

| Stage | Participants | Assessments |
|---|---|---|
| Raw ESM file (`esm_cleaned_combined_2021-04-07.RData`) | **199** | 8,672 surveys (median 44/person, range 1–158) |
| ≥ 40 surveys (before complete-case filter) | 124 | 7,165 |
| Shipped per-person model files (complete cases, lagged outcome, ≥ 40 rows) | 105 | 5,852 rows (mean 55.7, SD 16.2, 40–108) |
| **Published** | **104** | **5,971** |

The proposal's "199" is the raw ESM count; the analytic sample is ~104. The small gaps (105 vs 104, 5,852 vs 5,971) come from slightly different filters: the paper counts complete surveys before the outcome is lagged, and drops people whose models failed to tune. These should close once the R pipeline runs.

## Design facts
- WashU undergrads, Oct 2018–Dec 2019; 4 surveys/day for 2 weeks (target 56).
- **Outcomes in the published paper: loneliness and procrastination only.** Studying is *not* in the final paper. The repo has old elastic-net results for 7 outcomes (prcrst, lonely, study, tired, sick, argument, interacted), but pre-split data ships only for prcrst and lonely.
- Prediction target: the outcome at the **next** survey (t+1), from features at t.
- Split: chronological, first 75 % train / last 25 % test, per person.
- Models: elastic net, BISCWIT, random forest (one Rmd each in `03-scripts/02-revision`).
- Feature sets (7 × with/without time = 14):
  - BFI-2: 15 facets, planned-missing design (3 of 12 items per trait per beep), imputed with Amelia (m = 1)
  - Affect: 10 items (afraid, angry, attentive, content, excited, goaldir, guilty, happy, proud, purposeful)
  - Binary situations: 18 items, including the outcomes themselves
  - DIAMONDS S8-I: 8 items
  - Time: day-of-week, time-of-day, linear/quadratic/cubic trend, 12 h and 24 h sine/cosine

## Things a replication should flag (from `01-data-cleaning.Rmd`)
1. **`night` dummy is always 0.** The code says `Hour >= 22 & Hour < 5`, which no hour can satisfy; it should be `|`.
2. **`evening` overlaps morning and midday.** The code says `Hour >= 5 & Hour < 22`; it probably should be `>= 17`.
3. **`linear` time trend is scaled across everyone, not per person.** `scale(cumsumT)` runs after `ungroup()`.
4. **Imputation leaks across the split.** Amelia runs on each person's whole series before the train/test split, so test-period information feeds the training features.
5. The cleaning step loads from a Google Sheet and from hard-coded `local_path`/`res_path` values, so it needs patching to run offline.

Items 1–4 are small, but they give a principled "re-analysis with corrected pipeline" angle on top of the extensions (cross-dataset transfer, temporal decay, pooled-centered vs idiographic).

## Step 2: reran their R cleaning pipeline

Setup:
- R 4.6.1 via Homebrew; packages in `Rlib/`.
- Run with `R_LIBS_USER=$PWD/Rlib Rscript scripts/run_cleaning.R upstream/behavior-prediction`.
- The runner extracts the chunks from `01-data-cleaning.Rmd`, points the paths at the clone and skips the final `rm(list = ls())`. Output goes to `derived/all_features.RData` and `derived/cleaning_run.log`.
- `tidyverse` itself won't install (missing system font libs for `ragg`/`textshaping`), so the runner loads its components. `vip` isn't on CRAN for R 4.6; it's only needed for variable importance later.

The pipeline runs cleanly. **The published 104 / 5,971 is not reproduced exactly** by any filter I tried (`scripts/run_cleaning.R`, `scripts/sample_variants.R`):

| Definition | N | Assessments |
|---|---|---|
| **Published** | **104** | **5,971** |
| Their code's own final summary (≥ 40, has a glmnet model for any of 7 outcomes) | 113 | 6,751 |
| ≥ 40 complete surveys, has a model for lonely or prcrst | 99 | 5,913 |
| People in the shipped model files, no ≥ 40 cut | 105 | 5,921 |
| ≥ 40 complete surveys, with DIAMONDS included in the completeness check | 104 | 6,060 |

5. **The `"SI-8"` typo.** The demographics filter uses `category %in% c(..., "SI-8")`, but the category is `"S8-I"`, so DIAMONDS never enters the complete-case check. With it fixed, N becomes exactly 104, so the published N may come from a version of the code without the typo. The assessment count still doesn't match.
6. My two counting routes disagree slightly on the same people (5,913 vs 5,707). The likely cause is grouped vs ungrouped data going into `pivot_wider`; not yet resolved.

The gap is 1–2 %, which doesn't threaten the paper's conclusions, but a replication paper should report it. It's also worth emailing the first author for the exact filter.

## Step 3: reran the elastic net (glmnet) on their shipped train/test splits

`scripts/run_glmnet.R` is a copy of `elnet_fun` from `02-elastic-net.Rmd`:
- rolling-origin CV (initial 15, assess 1)
- 10 × 10 penalty/mixture grid
- best model chosen by CV **accuracy**

Note that the paper text says 10-fold CV tuned on MAE; the code does neither.

Three adaptations were needed for current tidymodels:
- No `prep()` before adding the recipe to the workflow.
- Constant factors are dropped. This catches `night`, which is always 0 (bug 1).
- **`Tue` is added to `dummy_vars`.** The original lists `"Tues"`, so `Tue` stays a factor and every time-feature model fails with "non-numeric column" (bug 7).

Of 1,885 models, 1,871 ran. The 14 failures are mostly participant 113, whose early CV folds are constant. Published glmnet results come from `05-results/final-model-performance.RData`; scripts are `scripts/compare_glmnet.R` and `derived/glmnet_comparison.csv`.

| | Loneliness | Procrastination |
|---|---|---|
| Models in both runs | 651 | 1,117 |
| Accuracy: exact match | 63 % | 50 % |
| Accuracy: r (rerun vs published) | .78 | .76 |
| Accuracy: mean rerun / published | .823 / .831 | .757 / .765 |
| **AUC: r (rerun vs published)** | **−.02** | **.01** |
| AUC: exact match | 4 % | 6 % |
| AUC: mean rerun / published | .536 / .531 | .499 / .514 |

**Per-model AUC does not replicate at all; aggregate means do (≈ .50–.54, i.e. chance).** The AUC changes when the chosen penalty changes, and many grid points tie on CV accuracy. Within one model the tied candidates gave test AUCs of 0.5 or 0.8, while the published value was 0.0. Test sets are tiny (median 14 observations, **median 2 positives**), so AUC can only take a few values and swings wildly.

### Benchmark 1: "always predict the usual answer" (`scripts/majority_baseline.R`)
This predicts each person's most common training outcome for every test observation.

| | Loneliness | Procrastination |
|---|---|---|
| Baseline accuracy | **.866** | **.797** |
| Published elastic-net accuracy | .831 | .765 |
| Published models beating the baseline | 4 % | 12 % |
| … tying it | 74 % | 59 % |
| … worse than it | 22 % | 29 % |

The ~80 % accuracy reported is **below a no-features baseline** on average. Most models just predict the majority class.

### Benchmark 2: the paper's "best model" rule applied to noise (`scripts/best_of_null.R`)
`05-summary.Rmd` (Figure 1) picks each person's best model as the **highest test-set AUC** across 6 candidates (psych / situations / full × time / no time), excluding AUC = 1. That is model selection on the test set. Replacing every candidate's predictions with random numbers and applying the same rule (200 simulations):

| Best-of-6 test AUC | Loneliness mean (median) | Procrastination mean (median) |
|---|---|---|
| Published | .685 (.737) | .733 (.760) |
| Rerun | .730 (.750) | .688 (.704) |
| **Random scores** | **.761 (.782)** | **.742 (.760)** |

**Random predictions match or beat the published "best models."** Caveat: random scores never tie, while a heavily penalised glmnet often predicts a constant (AUC .5), so this null is slightly generous to noise. That doesn't change the conclusion that the headline numbers can't be told apart from chance.

## Step 4: reran BISCWIT and random forest

Runners: `scripts/run_biscwit.R` (copy of `biscwit_fun`) and `scripts/run_rf.R` (copy of `rf_fun`). Comparison: `scripts/compare_models.R --model=…`. Both benchmark scripts take the model name; outputs are `derived/<model>_*.csv`.

- **BISCWIT:** 1,853 / 1,885 ran. 32 failed inside `bestScales` ("no items met the criteria"), which the original's `possibly()` also swallowed.
- **Random forest:** 1,884 / 1,885 ran, after one adaptation. `step_zv(contains(dummy_vars))` also matches the outcome `o_value_1`, so the recipe deleted the outcome whenever it was constant in a CV fold and current `tune` failed 340 models. I excluded the outcome from that step (bug 9).
- RF builds its own split from `02-model-data`: log-transform + differencing of continuous features, then lag-1 embedding. So the previous value of the outcome is a predictor.

More code issues:

8. **BISCWIT AUC is inverted.** `roc_auc(truth = crit_actual, crit_predicted)` uses yardstick's default event level, `"0"`, but higher predictions mean outcome 1. The runner also records the corrected AUC (`roc_auc_event1`), which is exactly 1 − published-style AUC.
9. **BISCWIT tuning picks the largest |r|.** `arrange(desc(abs(merror)))`, so **49.7 % of the chosen BISCWIT models had a negative validation correlation**, i.e. they were selected because they anti-predict.
10. RF's `step_zv(contains(dummy_vars))` also hits the outcome (see above). Also, binary situation items not listed in RF's `dummy_vars` (e.g. `lonely` when predicting procrastination) get log-transformed: log(0) = −Inf.

### All three methods, side by side

**Per-model replication (rerun vs published, same person × outcome × feature set):**

| | glmnet lonely | glmnet prcrst | BISCWIT lonely | BISCWIT prcrst | RF lonely | RF prcrst |
|---|---|---|---|---|---|---|
| Accuracy exact match | 63 % | 50 % | 63 % | 46 % | 71 % | 61 % |
| Accuracy r | .78 | .76 | .78 | .78 | .74 | .84 |
| **AUC r** | **−.02** | **.01** | **−.02** | **.08** | **.04** | **.06** |
| Mean AUC rerun / published | .536 / .531 | .499 / .514 | .467 / .491 | .492 / .488 | .618 / .516 | .558 / .516 |

**Benchmark 1, accuracy vs always predicting the usual answer:**

| | glmnet lonely | glmnet prcrst | BISCWIT lonely | BISCWIT prcrst | RF lonely | RF prcrst |
|---|---|---|---|---|---|---|
| Baseline accuracy | .866 | .797 | .866 | .797 | .851* | .789* |
| Published accuracy | .831 | .765 | .845 | .766 | .856 | .782 |
| Published models beating baseline | 4 % | 12 % | 6 % | 18 % | 16 % | 18 % |
| Published models worse than baseline | 22 % | 29 % | 23 % | 34 % | 10 % | 19 % |

\*RF uses its own test sets; its baseline is "always predict 0" (0 is the training majority in 96 % of the shipped splits, so this baseline is slightly weaker than the true majority rule).

**Benchmark 2, the paper's best-of-6 rule (mean test AUC per person):**

| | glmnet lonely | glmnet prcrst | BISCWIT lonely | BISCWIT prcrst | RF lonely | RF prcrst |
|---|---|---|---|---|---|---|
| Published | .685 | .733 | .686 | .674 | .635 | .660 |
| Rerun | .730 | .688 | .704 | .712 | .789 | .734 |
| **Random scores** | **.761** | **.742** | **.761** | **.742** | **.761** | **.742** |

Every published method's best-of-6 AUC is **below** what random scores reach under the same rule.

**One open thread: RF.** RF is the only method whose rerun mean AUC is clearly above .5: .62 for loneliness and .56 for procrastination, vs .52 published. Its rerun best-of-6 for loneliness (.789) also edges past the random null. A plausible reason is that RF alone includes the previous value of the outcome as a predictor, so it can pick up autocorrelation. The gap to the published RF numbers is unexplained; ranger/dials versions change the random tuning grid. This is worth a dedicated check (RF with vs without the lagged outcome) because it bears directly on "is there any idiographic signal at all."

## Step 5: where does RF's signal come from? (and what the labels really are)

### RF with vs without the lagged outcome (`scripts/run_rf.R --lag=…`, `scripts/compare_rf_lag.R`)
All variants use identical rows and test sets (verified).

| Person-level mean AUC [95 % CI] | Loneliness (N = 57–58) | Procrastination (N = 97–98) |
|---|---|---|
| RF, full (rerun) | **.603** [.562, .644] | **.548** [.521, .574] |
| RF, lagged outcome removed | .610 [.570, .650] | .545 [.520, .571] |
| RF, lagged outcome only | .490 [.461, .519] | .525 [.505, .546] |

**Autocorrelation isn't the source.** Removing the lagged outcome changes nothing; on its own it is at or near chance.

`scripts/person_level_auc.R` gives the same person-level test for every method (each person's AUC averaged over feature sets, then t-tested vs .5):

| | Loneliness | Procrastination |
|---|---|---|
| Published glmnet / BISCWIT / RF | .536 / .485 / .518 (all n.s.) | .512 / .486 / .518 (all n.s.) |
| Rerun glmnet / BISCWIT (event = 1) | .531 / .522 (n.s.) | .504 / .510 (n.s.) |
| **Rerun RF** | **.603, p < .001** | **.548, p < .001** |

### The shipped outcome labels are the PREVIOUS beep, not the next (`scripts/label_alignment.R`)
I rebuilt the outcome series from the raw data (`derived/all_features.RData`) and compared it with the shipped `o_value` in 8,198 model-data rows (one Affect file per person × outcome; the feature checked, `happy`, matches the rebuilt data in 100 % of rows):

| Shipped `o_value` equals… | Agreement |
|---|---|
| outcome at the same beep | .774 |
| next beep (text order) | .764 |
| next beep (clock order) | .762 |
| **previous beep (text order)** | **.992** |
| previous beep (clock order) | .948 |

11. **The shipped splits pair features at beep *t* with the outcome reported at beep *t − 1*.** So every published model "predicts" the past, not the future. The current `data_fun` uses `lead()`, so the shipped files must come from a different (earlier) version of the code. The published results were fitted on these files: accuracy matches my rerun exactly in 50–70 % of models.
12. **"Previous/next beep" uses text sort order.** `Full_Date` hours aren't zero-padded ("8:44" sorts after "21:00"). 12 % of beeps have one-digit hours, and in 224 of 398 person × outcome series the text order differs from the clock order.
13. **Test labels are fabricated when a test set is one-class.** `save_fun` runs `test_fun` over `dummy_vars`, which includes `o_value`. When the test outcome has one class, a random test label is flipped to the other class (`train_fun` does the same in training when a class appears < 2 times). 48.7 % of test sets have exactly one minority-class observation. The ~0.8 % residual disagreement above is consistent with these injected labels.

**What this means for RF.** RF's lag embedding adds each feature's previous-beep value (`*_2`). Because the label is also from the previous beep, those `*_2` features come from **the same survey as the label**. RF's above-chance AUC may therefore be a concurrent association ("how I feel in this survey" ↔ "did I procrastinate in the hour before this survey"), not prediction. Tested with `--lag=no_same_survey` (drop all `*_2` columns; same rows):

| Person-level mean AUC [95 % CI] | Loneliness | Procrastination |
|---|---|---|
| RF, full (rerun) | .603 [.562, .644] | .548 [.521, .574] |
| RF, same-survey features removed | .567 [.530, .605], p < .001 | .520 [.497, .543], p = .09 |
| Paired drop (full − removed) | .035 [.005, .066], p = .02 | .028 [.007, .048], p = .008 |

- **Procrastination:** RF's signal is fully explained by same-survey association; without it, AUC is at chance.
- **Loneliness:** about a third of the excess is same-survey. The remaining .567 comes from features at beep *t* "predicting" loneliness reported at beep *t − 1*. That is still backwards in time, but loneliness is a slow-moving state, so a nearby survey carries information about it.
- **No model in this study demonstrates prediction of a future behaviour.** All labels are past ones (bug 11). The only above-chance results come from RF in the current software, and they are explained by same-survey or adjacent-state association.
- The gap between rerun RF (.60 / .55) and published RF (.52 / .52) is still unexplained. Old vs new ranger/dials (the random tuning grid) is the likely cause; pinning 2021 package versions would settle it.

### Implications for the paper idea
- The strongest contribution is now a **critical replication**: the per-person elastic-net results are consistent with chance once you compare against a majority-class baseline and against best-of-k selection on the test set.
- Bugs 1, 2, 5 and 7 and the methods/code mismatch (CV scheme, tuning metric) are supporting detail.
- This now holds for **all three methods**. None of them beat a majority-class baseline on average, and every published best-of-6 summary is below a random-score null.
- **The biggest problem is bug 11: the shipped data predict the previous beep's outcome.** Before writing anything up, email the first author with the alignment table. There may be an explanation (e.g. a deliberate re-definition of the target that the paper doesn't describe), and a critical replication should give them the chance to respond.
- Next steps:
  1. **Rebuild the splits correctly** from `derived/all_features.RData`: true next beep in clock order, no injected labels, no `night`/`Tues`/`SI-8` bugs. Rerun all three methods on that, under both benchmarks. That's the "corrected re-analysis".
  2. **A pooled model with person-mean centering vs the idiographic models**, on the corrected splits. That's the constructive half of the paper.
  3. Evaluate on longer test windows, or pool test predictions across people, so AUC isn't computed on 1–2 positives.
  4. Optional: pin 2021 package versions to explain the rerun RF vs published RF gap.

---

## Step 6: Corrected-split rerun results (2026-10-30)

Rebuilt all 1,870 splits from `derived/all_features.RData` with the following fixes:
- `o_value` = outcome at **next** observed beep in clock order (not previous)
- `Full_Date` zero-padded so text sort = clock sort
- No label injection for one-class test sets
- Time features corrected (night = 22–05, evening = 17–22)
- Constant features dropped based on training rows only
- BISCWIT uses signed r (not |r|); RF log-transforms only positive columns

### Completion
| Method  | Models OK | Errors |
|---------|-----------|--------|
| BISCWIT | 1,841     | 29     |
| RF      | 1,869     | 1      |
| glmnet  | 1,854     | 16     |

### Per-model-split accuracy (mean across all 14 feature sets)
| Method  | Outcome | Splits | Accuracy | Majority (test) | Beats majority |
|---------|---------|--------|----------|------------------|----------------|
| BISCWIT | lonely  | 678    | .868     | .888             | 0%             |
| BISCWIT | prcrst  | 1,163  | .774     | .820             | 0%             |
| glmnet  | lonely  | 676    | .832     | .886             | 0%             |
| glmnet  | prcrst  | 1,178  | .770     | .820             | 0%             |
| RF      | lonely  | 692    | .881     | .887             | 0%             |
| RF      | prcrst  | 1,177  | .804     | .820             | 0%             |

No method beats the majority-class baseline on accuracy for either outcome.

### Person-level AUC (all 14 feature sets, persons as units)
| Method  | Outcome | N  | Mean AUC | 95% CI       | p vs .5 | Persist AUC | p vs persist |
|---------|---------|----|----------|--------------|---------|-------------|--------------|
| BISCWIT | lonely  | 38 | .561     | [.507, .616] | .029    | .543        | .500         |
| BISCWIT | prcrst  | 71 | .504     | [.472, .536] | .827    | .515        | .488         |
| glmnet  | lonely  | 38 | .541     | [.488, .594] | .126    | .537        | .865         |
| glmnet  | prcrst  | 72 | .498     | [.467, .530] | .925    | .514        | .346         |
| RF      | lonely  | 39 | .531     | [.474, .587] | .277    | .547        | .555         |
| RF      | prcrst  | 72 | .516     | [.482, .549] | .360    | .514        | .907         |

Persistence benchmark alone: loneliness .547 (p = .066), procrastination .514 (p = .369).

### Key takeaway
With correct labels (next beep, clock order, no injection):
1. **No method significantly beats persistence** for either outcome.
2. Only BISCWIT for loneliness (.561) is significantly above chance (p = .029), but the effect is small and does not exceed persistence (.543, p = .500 for the difference).
3. **RF's signal disappears entirely.** On the shipped (backward) labels, RF had AUC .603/.548 (lonely/prcrst); on corrected labels, .531/.516 — neither significant.
4. Elastic net is not significant for any outcome.
5. The original paper's above-chance results were driven by the backward-label bug: models were predicting the previous beep's outcome from the current beep's features (including same-beep situational items that share variance with the outcome).

### Step 6b: Pooled person-mean-centered model (2026-10-30)

One regularized logistic regression (glmnet, alpha = 0.5) per feature set × outcome, trained on all people's stacked data. Numeric features split into within-person (x − person mean) and between-person (person mean) components; factor features kept as-is. Evaluated per person on each person's test set.

| Method        | Outcome | N  | Mean AUC | p vs .5 | vs Persistence | vs Idiographic glmnet |
|---------------|---------|-----|----------|---------|----------------|----------------------|
| pooled_glmnet | lonely  | 39  | .507     | .477    | −.031, p=.146  | −.036, p=.210        |
| pooled_glmnet | prcrst  | 72  | .522     | .012    | +.008, p=.627  | +.023, p=.173        |

The pooled model for procrastination is significantly above chance (.522, p = .012) but the effect is tiny and does not beat persistence. For loneliness, the pooled model is worse than every idiographic method and indistinguishable from chance.

**Pooling does not help.** Neither the idiographic nor the pooled approach produces clinically or practically meaningful prediction of next-beep states from 2-week ESM data.

### All methods ranked (person-level mean AUC, all 14 feature sets)

| Rank | Model         | Lonely AUC (p) | Prcrst AUC (p) |
|------|---------------|-----------------|-----------------|
| 1    | BISCWIT       | .561 (.029)     | .504 (.827)     |
| 2    | idio glmnet   | .541 (.126)     | .498 (.925)     |
| 3    | RF            | .531 (.277)     | .516 (.360)     |
| 4    | pooled glmnet | .507 (.477)     | .522 (.012)     |
| —    | persistence   | .547 (.066)     | .514 (.369)     |

### What this means for the paper
The corrected rerun confirms a **null result**: idiographic models from 2-week ESM data do not predict next-beep loneliness or procrastination above persistence or chance, across all three methods. The pooled person-mean-centered model does not improve on the idiographic approach for either outcome. The paper's main claim — that idiographic models can achieve above-chance prediction — rests on data that used the wrong lag direction.

## Files
- `scripts/inspect_data.py`, `scripts/rdata_peek.py`, `scripts/count_sample.py`: Python readers (run with `.venv/bin/python -I`)
- `scripts/tree.json`: GitHub file tree snapshot (truncated by the API at 52k entries)
- `scripts/build_corrected_splits.R`: Rebuilds splits with all fixes
- `scripts/corrected_summary.R`: Three-method summary with benchmarks
- `scripts/run_with_memory_guard.sh`: Memory-guarded runner for long jobs
- `derived/corrected/corrected_model_results.csv`: Per-split results
- `derived/corrected/corrected_person_level.csv`: Person-level AUC summaries

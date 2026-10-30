# Idiographic Prediction of Daily Loneliness and Procrastination Does Not Exceed Chance: A Replication and Correction of Beck and Jackson (2022)

Pankaj Kumar

---

## Abstract

Beck and Jackson (2022, *Psychological Science*) reported that idiographic machine-learning models—elastic net, BISCWIT, and random forest—could predict next-survey loneliness and procrastination from experience-sampling data. I attempted a direct replication using the publicly available code and data. Three issues in the data-processing pipeline were identified: (a) the outcome variable paired each survey's features with the outcome reported at the *previous* survey rather than the next, reversing the intended prediction direction; (b) timestamps were sorted lexicographically rather than chronologically, altering the temporal order for 56% of participant–outcome series; and (c) test-set labels were modified when only one outcome class was present, affecting 49% of test sets. After correcting these issues and rerunning all three methods on 1,870 model splits across 104 participants, no method produced person-level AUC significantly above persistence (predicting the current state continues). A pooled person-mean-centered logistic regression also failed to improve on the idiographic approach. The original paper's above-chance results appear attributable to the backward-label alignment, which allowed models to exploit concurrent rather than prospective associations. These findings suggest that two weeks of four-daily experience-sampling surveys may not provide sufficient data for reliable idiographic behavioral prediction.

**Keywords:** idiographic prediction, experience sampling, machine learning, replication, loneliness, procrastination

---

## Introduction

The promise of idiographic—person-specific—prediction models is central to precision psychological science. If everyday behaviors and experiences can be predicted from a person's own recent history, interventions could be timed to moments of vulnerability. Beck and Jackson (2022) tested this idea using experience-sampling data from 104 undergraduates who completed four surveys per day for two weeks. They fitted elastic net, BISCWIT (Best Items Scale that is Cross-Validated, Informative, and Transparent), and random forest models for each participant, predicting whether the participant would report loneliness or procrastination at the next survey from features measured at the current survey. The paper reported that idiographic models achieved above-chance prediction for both outcomes.

The study was notable for its transparency: the full code and data were posted on GitHub (https://github.com/emoriebeck/behavior-prediction), enabling detailed inspection and replication. The present work takes advantage of that openness. I reran the published pipeline, identified three data-processing issues that affected the prediction target, corrected them, and reran all analyses. I also tested whether a pooled model with person-mean centering—leveraging both within- and between-person variation—could outperform the idiographic approach.

## Method

### Original Study Design

Participants were 104 undergraduates at Washington University in St. Louis (October 2018–December 2019) who completed at least 40 of a possible 56 experience-sampling surveys (4 per day for 14 days). Each survey measured 10 affect items, 18 binary situational items, 8 DIAMONDS situation perception items, and 15 BFI-2 personality facets (planned-missing design, imputed with Amelia). Two binary outcomes were analyzed: loneliness and procrastination.

The prediction target, as described in the paper, was the outcome at the *next* survey (*t* + 1) from features measured at survey *t*. Data were split chronologically (75% training, 25% test) within each participant. Three methods were applied across 14 feature-set combinations (7 feature groups × with/without time features): regularized logistic regression (elastic net via glmnet), BISCWIT (bestScales), and random forest (ranger).

### Replication Procedure

I cloned the repository at commit `24ab1c0` (25 January 2022) and reran all three model-fitting scripts using R 4.6.1 on macOS, with current package versions. The rerun used the shipped train/test split files in `04-data/`.

### Issues Identified

Three issues in the data-processing pipeline were identified through systematic comparison of the shipped model files against outcome series rebuilt from the raw data.

**Issue 1: Backward outcome alignment.** I compared the shipped `o_value` (the prediction target) in 8,198 model-data rows against outcome series reconstructed from the raw experience-sampling data. Features matched the raw data exactly (e.g., `happy` agreed in 100% of rows). However, `o_value` matched the *previous* survey's outcome 99.2% of the time, the *next* survey's outcome only 76.4% of the time, and the *same* survey's outcome 77.4% of the time. The current source code uses `lead()` to create the next-survey target, suggesting the shipped files were generated by an earlier version of the pipeline. Published model accuracies matched my rerun on these files in 50–70% of models, confirming the paper's results were based on the shipped (backward-aligned) data.

**Issue 2: Lexicographic timestamp sorting.** The `Full_Date` variable stored hours without zero-padding (e.g., "8:44" instead of "08:44"), causing string-based sorting to place "8:44" after "21:00". In 224 of 398 participant × outcome series (56%), lexicographic order differed from chronological order. Because the pipeline used `arrange(Full_Date)` to determine survey order, this affected which survey counted as "next" or "previous."

**Issue 3: Test-label modification.** The outcome variable `o_value` was included in the `dummy_vars` list, which triggered a function (`test_fun`/`train_fun`) that randomly flipped one label when a binary variable had only one class. When applied to the outcome in one-class test sets, this injected a single minority-class observation. Approximately 48.7% of test sets contained exactly one such injected label. In correspondence, the original author confirmed this adjustment was intentional, following consultation with a quantitative colleague, as part of a strategy to retain performance estimates for single-class test sets rather than excluding them.

### Corrected Re-Analysis

I rebuilt all splits from the raw feature data (`all_features.RData`) with the following corrections:

1. `o_value` set to the outcome at the *next* observed survey in chronological order
2. `Full_Date` zero-padded to ensure string sort equals clock sort
3. No label modification for one-class test sets (AUC left undefined)
4. Time features corrected: `night` = hour ≥ 22 or hour < 5 (the original used `and`, yielding all zeros); `evening` = 17–22
5. Constant features dropped based on training rows only
6. BISCWIT item selection by signed correlation (not absolute value, which selected 49.7% anti-predictive items)
7. Random forest log-transformation applied only to columns with all positive values (avoiding log(0) on binary items)

This produced 1,870 model splits across 104 participants. All three methods were rerun on the corrected splits.

### Pooled Person-Mean-Centered Model

To test whether aggregating across participants could improve prediction, I fitted a pooled regularized logistic regression (glmnet, α = 0.5) for each feature-set × outcome combination. Numeric features were decomposed into within-person (deviation from the person's training-set mean) and between-person (the person mean) components. The model was trained on all participants' pooled training data and evaluated on each participant's test set separately, yielding person-level AUC estimates comparable to the idiographic models.

### Benchmarks

Three benchmarks were used:

1. **Majority class:** Accuracy of always predicting the test set's most common outcome (a generous benchmark that peeks at test labels).
2. **Chance:** Person-level mean AUC tested against 0.5.
3. **Persistence:** Using the current survey's outcome as the prediction for the next survey's outcome, evaluated on the same test rows.

### Author Correspondence

Prior to preparing this manuscript, I contacted the first author with the three issues described above. Dr. Beck responded promptly and constructively, acknowledging a possible issue with the timestamp ordering and indicating she would trace how it affected the outcome alignment. She confirmed the label modification was intentional and noted that subsequent work in preparation adopts more stringent class-balance criteria. She requested the analysis scripts and a worked example, which were provided.

## Results

### Replication on Shipped Data

On the shipped (uncorrected) splits, per-model AUC showed essentially zero correlation between my rerun and the published values for all three methods (r = −.02 to .08), despite accuracy correlations of .74–.84. This discrepancy arose because many models produced tied CV accuracies, and different tie-breaking led to different penalty values and thus different test-set AUCs—which could swing from 0.0 to 0.8 on test sets with a median of 2 positive cases.

No method's mean accuracy exceeded a majority-class baseline (.87 for loneliness, .80 for procrastination). Applying the paper's "best model" selection rule (highest test-set AUC across 6 feature-set candidates) to random scores produced AUCs of .76/.74 (loneliness/procrastination)—matching or exceeding every published method, confirming that the selection procedure capitalized on chance.

The one exception was random forest in the rerun, which showed above-chance person-level AUC (.603 for loneliness, .548 for procrastination). However, RF uniquely includes lag-1 feature embeddings, and because the shipped labels were backward-aligned, these lag features came from the *same* survey as the label. Removing same-survey features reduced RF's loneliness AUC from .603 to .567 and procrastination from .548 to .520 (not significant), confirming the signal was concurrent association rather than prediction.

### Corrected Re-Analysis

Table 1 shows person-level AUC for all methods on the corrected splits.

**Table 1.** Person-level mean AUC across all 14 feature sets, corrected splits.

| Method        | Outcome         | *N*  | Mean AUC | 95% CI       | *p* vs .50 | Persistence AUC | *p* vs persistence |
|---------------|-----------------|------|----------|--------------|------------|-----------------|-------------------|
| BISCWIT       | Loneliness      | 38   | .561     | [.507, .616] | .029       | .543            | .500              |
| Elastic net   | Loneliness      | 38   | .541     | [.488, .594] | .126       | .537            | .865              |
| Random forest | Loneliness      | 39   | .531     | [.474, .587] | .277       | .547            | .555              |
| Pooled glmnet | Loneliness      | 39   | .507     | [.487, .527] | .477       | —               | .146              |
| BISCWIT       | Procrastination | 71   | .504     | [.472, .536] | .827       | .515            | .488              |
| Elastic net   | Procrastination | 72   | .498     | [.467, .530] | .925       | .514            | .346              |
| Random forest | Procrastination | 72   | .516     | [.482, .549] | .360       | .514            | .907              |
| Pooled glmnet | Procrastination | 72   | .522     | [.505, .538] | .012       | —               | .627              |

*Note.* Persistence = AUC of using the current survey's outcome as the score for the next survey. Person-level AUC is each participant's mean AUC across feature sets with defined AUC (test sets with one outcome class excluded). *p* vs .50 is a one-sample *t*-test; *p* vs persistence is a paired *t*-test on person-level AUC differences. The persistence benchmark itself: loneliness .547, *p* = .066; procrastination .514, *p* = .369.

No method produced accuracy above the majority-class baseline for either outcome (0% of splits beat the baseline across all methods).

### Key Comparisons

1. **No method significantly exceeded persistence** for either outcome. The largest difference was BISCWIT for loneliness (+.018 over persistence), which was not significant (*p* = .500).

2. **Random forest's signal disappeared.** On shipped data, RF achieved person-level AUC of .603/.548 (loneliness/procrastination); on corrected data, .531/.516—neither significant. The original signal was attributable to concurrent same-survey associations enabled by the backward label alignment.

3. **The pooled model did not improve on idiographic models.** Pooled glmnet produced AUC of .507 for loneliness (below every idiographic method) and .522 for procrastination (significantly above chance but not above persistence). The paired difference between pooled and idiographic glmnet was not significant for either outcome (loneliness: −.036, *p* = .210; procrastination: +.023, *p* = .173).

4. **Only BISCWIT for loneliness exceeded chance** (.561, *p* = .029), but the effect was small (Cohen's *d* ≈ 0.37) and did not survive comparison to persistence.

## Discussion

The present replication identified three data-processing issues in Beck and Jackson (2022) that collectively reversed the direction of prediction: models were fitted to predict the *previous* survey's outcome from the current survey's features, rather than the next survey's as intended and described. After correction, none of the three idiographic methods—elastic net, BISCWIT, or random forest—predicted next-survey loneliness or procrastination significantly above a persistence baseline. A pooled person-mean-centered model also failed to improve prediction. The original paper's above-chance results appear to have been driven by the backward-label alignment, which allowed models to exploit concurrent or near-concurrent associations rather than prospective ones.

### The Role of Each Issue

The backward outcome alignment (Issue 1) was the primary driver. By pairing features at survey *t* with the outcome at survey *t* − 1, models could leverage within-survey covariance—particularly in the random forest, whose lag-1 feature embedding placed same-survey features alongside the target label. The timestamp sorting issue (Issue 2) compounded this by altering which surveys were considered adjacent, though its effect is secondary to the direction reversal. The label modification (Issue 3) was intentional and its impact on aggregate results was likely small, though it introduced noise into individual test-set AUCs.

### Why the Null Result Is Not Surprising

Two weeks of four-daily surveys yields approximately 42 usable observations per participant after missing data. With a 75/25 split, training sets contain roughly 30 observations and test sets roughly 10—too few for stable estimation of individual prediction models with 20–60 features, and too few for AUC to be a reliable discriminability metric. The persistence benchmark (.547/.514) was itself not significantly above chance, suggesting that even the simplest temporal regularity is hard to detect at this sample size. These constraints are not specific to the methods used; they reflect fundamental limits of short-burst experience-sampling designs for idiographic prediction.

### Relation to the Original Authors' Response

Dr. Beck acknowledged the possible timestamp-ordering issue and indicated she would trace its effect on the outcome alignment. She confirmed the label modification was intentional, noting that subsequent work adopts stricter class-balance criteria. She also offered a second dataset with similar measures but different sampling parameters (5 surveys per day over a longer period), which could provide an independent test of idiographic prediction with more observations per person. This constructive engagement reflects the value of open science practices—the public availability of code and data made this replication possible and facilitated productive dialogue.

### Limitations

This replication used current R package versions rather than the exact versions used in the original study. Although this explains small discrepancies in model tuning (particularly for random forest, whose rerun AUC was higher than published on the shipped data), it does not affect the corrected re-analysis, which used a consistent pipeline throughout. The BFI-2 features differ slightly between the shipped and rebuilt data due to re-running the Amelia imputation, though affect and situational features matched exactly. The imputation-leakage issue (Amelia run on the full series before splitting) was not corrected in this replication, as it was present in both the original and corrected analyses; fixing it would likely reduce rather than improve prediction.

### Conclusion

The finding that idiographic machine-learning models can predict next-survey behaviors from experience-sampling data (Beck & Jackson, 2022) does not survive correction of the outcome alignment. With the prediction target properly set to the next survey in chronological order, no method exceeds persistence or chance. Pooling across participants with person-mean centering does not help. These results suggest that short-burst experience-sampling designs (2 weeks, 4 surveys/day) may not provide sufficient within-person observations for reliable idiographic behavioral prediction, even with flexible machine-learning methods. Future work should investigate whether longer sampling periods, higher survey frequency, or more temporally stable outcomes yield different conclusions.

## References

Beck, E. D., & Jackson, J. J. (2022). Personalized prediction of behaviors and experiences: An idiographic person–situation test. *Psychological Science*, *33*(10), 1767–1782. https://doi.org/10.1177/09567976221093307

## Data and Code Availability

All analysis scripts, corrected split-building code, and result files are available at [repository URL to be added]. The original data and code are available at https://github.com/emoriebeck/behavior-prediction.

---

*Correspondence:* Pankaj Kumar, pankajator@gmail.com

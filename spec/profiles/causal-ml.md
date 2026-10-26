# Profile `causal-ml/0.1`

Status: draft. Schema: [`schema/profiles/causal-ml-0.1.json`](../../schema/profiles/causal-ml-0.1.json).
Kind: standard. Builds on the core only.

Causal estimates that use machine-learning models for the nuisance functions: double/debiased
machine learning, generalized random forests and causal forests, and meta-learners. Surveyed
2026-10-25 from source: DoubleML 0.11.4 (Python), EconML 0.17.0 and R grf 2.6.1
(grf-labs/grf @ 5bee99b). DoubleML for R follows the Python package's conventions.

## Requirements

- `meta.estimator.method`: `dml_plr`, `dml_irm`, `dml_pliv`, `dml_iivm`, `dml_did`,
  `linear_dml`, `sparse_linear_dml`, `causal_forest`, `instrumental_forest`, `dr_learner`,
  `s_learner`, `t_learner`, `x_learner`, `r_learner`, `orthogonal_forest`.
- `specification.causal` with `treatment`, `outcome` and `estimand`.
- `specification.learners`: each nuisance model by role, with its class and resolved
  hyperparameters.
- `specification.cross_fitting` with `n_folds`, `n_repeats` and `seed` (`null` when none was
  set).
- At least one row with a `causal` object naming its estimand, with `estimate` and
  `std_error`.
- `metrics.nobs`.

## Defaults that change results

| | DoubleML | EconML (DML family) | grf `causal_forest` |
|---|---|---|---|
| Folds | `n_folds = 5` | **`cv = 2`** | out-of-bag (honest forests) |
| Repetitions | `n_rep = 1` | `mc_iters = None` (1) | — |
| Aggregation over repetitions | **median** | **mean** (`mc_agg`) | — |
| Seed | numpy's global RNG and the learners' `random_state` | `random_state` | **drawn at random** (`seed = runif(...)`) unless set |
| Trees | (learner) | `CausalForestDML`: `n_estimators = 100`, `max_samples = 0.45` | `num.trees = 2000`, `sample.fraction = 0.5` |
| Overlap | IRM `trimming_rule = "truncate"`, `trimming_threshold = 0.01` | | `average_treatment_effect(target.sample = "all")` |
| ATE method | the orthogonal `score` | | `method = "AIPW"` (or `"TMLE"`) |

Cross-fitted estimates depend on the sample split, so with a single repetition two runs with
different seeds differ; a grf forest without a seed is not reproducible. `cross_fitting.seed`
is therefore required, and `per_repeat` on the row keeps each repetition's estimate before
aggregation.

## `specification.causal` and `learners`

| Name | DoubleML | EconML | grf |
|---|---|---|---|
| `treatment`, `outcome` | `d_cols`, `y_col` | `T`, `Y` | `W`, `Y` |
| `controls` | `x_cols` | `W` (and `X`) | `X` |
| `effect_modifiers` | | `X` | `X` |
| `instruments` | `z_cols` | `Z` | `Z` (`instrumental_forest`) |
| `estimand`, `score` | `score` (`"partialling out"`, `"IV-type"`; IRM `"ATE"`, `"ATTE"`) | `ate()`, `effect()` | `average_treatment_effect(target.sample, method)` |
| `clusters` | `cluster_cols` | | `clusters` |
| `learners` roles | `ml_l`, `ml_m`, `ml_g`, `ml_r` | `model_y`, `model_t`, `model_final` | `Y.hat`, `W.hat` forests |

`estimand` vocabulary: `ate`, `att`, `atc`, `late`, `ate_overlap`, `partial_linear`, `cate`,
`gate`, `blp`. Unit-level CATEs go in an attachment.

## Diagnostics

- `structures.nuisance`: out-of-fold losses per nuisance role (DoubleML `nuisance_loss`,
  `evaluate_learners()`; EconML `nuisance_scores_y`, `nuisance_scores_t`). Poorly fit nuisances
  are the usual reason two DML results disagree.
- `specification.overlap`: trimming rule and threshold, and the fitted propensity range.
- `structures.heterogeneity`: grf `test_calibration()`, `best_linear_projection()`,
  `variable_importance()`; DoubleML `cate()`.
- `structures.sensitivity`: DoubleML `sensitivity_analysis()` (cf_y, cf_d, rho, bounds,
  robustness values).

## Example

[`schema/examples/causal-ml.estimation.json`](../../schema/examples/causal-ml.estimation.json):
a real DoubleML partially linear model on simulated data with a known effect of 0.5 (estimate
0.502, SE 0.032), random-forest nuisances, 5-fold cross-fitting repeated 3 times with median
aggregation.

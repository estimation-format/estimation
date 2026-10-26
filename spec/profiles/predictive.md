# Profile `predictive/0.1`

Status: draft. Schema: [`schema/profiles/predictive-0.1.json`](../../schema/profiles/predictive-0.1.json).
Kind: standard. Builds on the core only.

Predictive (machine-learning) models, judged by out-of-sample performance rather than by
coefficients and standard errors. Surveyed 2026-10-25: from source, scikit-learn 1.9.1, XGBoost
3.4.1 and R ranger 0.18.0, tidymodels (rsample @ 3f43187, tune @ d047fc3, workflows @ 21ef53f), mlr3
(@ c7eeaf9, mlr3tuning @ 9220c89, mlr3mbo @ 17b27cd, mlr3pipelines @ 936c4ae) and caret 7.0-1
(cran/caret); LightGBM from documentation. caret's `trainControl()` defaults to the bootstrap
(25 resamples), not cross-validation. Deep
learning fits the same layout; framework-specific training logs were not surveyed.

The core already has `parameters[*].importance` and `rank`, the `hyperparameters` and `tree`
structures, and `provenance.environment` for threads, BLAS and GPU settings. This profile adds
what makes a predictive result checkable: how the data were split, what the model's settings
actually were, and which split each metric comes from.

## Requirements

- `meta.estimator.method` (`random_forest`, `gradient_boosting`, `lasso`, `elastic_net`, `svm`,
  `neural_network`, ...).
- `specification.task` with `type` (`binary_classification`, `multiclass_classification`,
  `regression`, `survival`, `ranking`, `multilabel`).
- `specification.validation` with `scheme` (`holdout`, `kfold`, `stratified_kfold`,
  `repeated_kfold`, `group_kfold`, `time_series_split`, `nested_cv`, `loo`, `bootstrap`, `oob`,
  `none`), plus folds, repeats, stratification, groups, shuffle and seed as they apply.
- `structures.hyperparameters`: `{kind: "object", values: {...}}` with **every**
  hyperparameter in effect, defaults included.
- `structures.evaluation`: at least one `{kind: "object", metric, split, value}`, with `sd`,
  `per_fold` and `definition` when relevant.

## Why defaults must be written out

The same call means different models in different libraries and versions:

| | scikit-learn | ranger | XGBoost |
|---|---|---|---|
| Trees | `n_estimators = 100` | `num.trees = 500` | `n_estimators` (100) |
| Features per split | classifier `"sqrt"`, regressor all (`1.0`) | `mtry = floor(sqrt(p))` | `colsample_*` (1) |
| Importance | `feature_importances_` (impurity) | `importance = "none"` unless set | `feature_importances_` (gain); `get_score()` (weight) |

`get_params()` (scikit-learn, XGBoost), `learner$param_set$values` (mlr3) and the parsnip spec
plus engine arguments (tidymodels) give the resolved values. Importance rows carry
`importance_type` (`impurity`, `permutation`, `gain`, `split`, `cover`, `shap_mean_abs`,
`coefficient`), since the types rank features differently.

## Leakage guards

Three fields record the common ways a reported metric becomes optimistic:

- `validation.preprocessing_in_resampling`: scaling, imputation, feature selection or target
  encoding fit inside each resample (a scikit-learn `Pipeline`, a tidymodels workflow, an mlr3
  `GraphLearner`). `false` means preprocessing saw the evaluation data.
- `early_stopping.eval_split`: the split monitored for early stopping (`validation`, `train`,
  `test`). `test` means the test metrics are optimistic.
- `evaluation[*].split`: `cv` and `oob` metrics are not test metrics; a tuned model's CV score
  is the score of the selected candidate and is optimistic for it.

`specification.tuning` records the search (`grid`, `random`, `bayesian`, `halving`), the
space, the number of candidates, the selection metric and rule (`best`, `one_se`), and whether
the model was refit.

## Metrics

`metric` vocabulary: `roc_auc`, `pr_auc`, `accuracy`, `balanced_accuracy`, `log_loss`,
`brier`, `f1`, `precision`, `recall`, `rmse`, `mae`, `r2`, `mape`, `c_index`, `ndcg`.
`definition` holds what is needed to recompute a metric: the averaging for multiclass metrics
(macro, micro, weighted), the classification threshold, the positive class.

The fitted model itself belongs in an attachment (with its sha256), not in the record.

## Example

[`schema/examples/predictive.estimation.json`](../../schema/examples/predictive.estimation.json):
a real scikit-learn random forest on the Wisconsin breast-cancer data, tuned by a 4-candidate
grid search with 5-fold stratified CV on a 75% training split and evaluated on the 25% test
split (ROC AUC 0.987 in CV, 0.998 on test).

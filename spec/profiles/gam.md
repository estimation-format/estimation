# Profile `gam/0.1`

Status: draft. Schema: [`schema/profiles/gam-0.1.json`](../../schema/profiles/gam-0.1.json).
Kind: standard. Builds on the core only.

Generalized additive models with penalized smooth terms. Surveyed 2026-10-25: from source, R
mgcv 1.9-4 (cran/mgcv @ 1b6a4c8) and pyGAM 0.12.0; statsmodels `GLMGam` from documentation.
GAMLSS and Bayesian GAMs (brms `s()`) were not surveyed; a Bayesian GAM claims
[`bayesian/0.1`](bayesian.md) as well.

## Requirements

- `specification.smooths`: one entry per smooth, `{term, variables, basis, k}` (plus `by`,
  `penalty_order`, `constraint`).
- `specification.options.smoothing_method`.
- A `smooth` object with `edf` on each smooth-term row; `estimate` and `std_error` on
  parametric rows.
- `metrics.nobs`.

GLM-style `meta.estimator.distribution` and `link` use [`glm/0.1`](glm.md)'s names.

## Settings that change the fit

| | mgcv `gam` | pyGAM | statsmodels `GLMGam` |
|---|---|---|---|
| `smoothing_method` | **`GCV.Cp`** (default; `REML` recommended, `ML`; `bam`: `fREML`) | grid search on GCV (unknown scale) or UBRE | fixed `alpha`, or `select_penweight` |
| `basis` | `bs = "tp"` (thin plate) | penalized B-splines (`ps`) | `BSplines`, `CyclicCubicSplines` |
| `k` | `k` (10 for a one-variable `tp`) | `n_splines` (20) | `df` |
| Extra shrinkage | `select = FALSE` | | |

The same formula fit by GCV and by REML can give noticeably different wiggliness, and `k`
caps how wiggly a smooth can be, so both are required.

## Smooth rows

`parameters[*].smooth`: `{edf, ref_df, statistic, p_value, smoothing_parameter, k}` (mgcv
`summary()$s.table`: `edf`, `Ref.df`, `F`/`Chi.sq`, `p-value`; `sp`. pyGAM `statistics_`:
`edof_per_coef` summed over the term, `p_values`; the term's `lam`). Basis coefficients are per
basis function: keep them in an attachment if needed.

Smooth-term p-values are approximate. mgcv's account for smoothing-parameter selection;
pyGAM's do not and are, as pyGAM itself warns, typically too small when smoothing parameters
were estimated.

## Metrics and structures

| Name | mgcv | pyGAM |
|---|---|---|
| `edf_total` | sum of `edf` | `edof` |
| `deviance_explained` | `summary()$dev.expl` | `pseudo_r2["explained_deviance"]` |
| `adj_r2` | `summary()$r.sq` | |
| `criterion` (`{value, definition}`) | `gcv.ubre` (REML/GCV score) | `GCV`, `UBRE` |
| `scale`, `log_lik`, `aic` | `sig2`, `logLik()`, `AIC()` | `scale`, `loglikelihood`, `AIC` |

`structures.basis_check` holds mgcv's `k.check()` (k′, edf, k-index, p-value per smooth);
`structures.concurvity` holds `concurvity()`.

## Example

[`schema/examples/gam.estimation.json`](../../schema/examples/gam.estimation.json): a real pyGAM
fit of head acceleration on time in the `mcycle` data, one 20-spline smooth with λ chosen by a
31-point GCV grid search (edf 11.0, deviance explained 0.80).

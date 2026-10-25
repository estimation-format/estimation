# Profile `sem/0.1`

Status: draft. Schema: [`schema/profiles/sem-0.1.json`](../../schema/profiles/sem-0.1.json).
Kind: standard. Builds on the core only.

Structural equation models: confirmatory factor analysis, path models and full SEMs, single-
or multi-group. Surveyed 2026-10-25: from source, lavaan 0.7-3.3357 (yrosseel/lavaan @
08683ee) and semopy 2.3.11; Stata `sem` and `estat gof` from documentation. Mplus, OpenMx,
`gsem` and Bayesian SEM (blavaan) were not surveyed. Indirect effects defined in a model are
also described by [`mediation/0.1`](mediation.md).

## Requirements

- `meta.estimator.method`: `ml`, `mlw` (Wishart), `mlr`, `mlm`, `mlmv`, `fiml`, `gls`,
  `wls`, `dwls`, `wlsmv`, `uls`, `adf`, `pml`, `bayes`.
- `specification.formula`: the model as written, `syntax` `lavaan`, `stata` or `semopy`.
- A `sem` object on every row that isn't dropped, with `estimate`; `std_error` on free
  parameters.
- `metrics.nobs`, `chisq` and `chisq_df`.
- A default vcov with `type`.
- `structures.numerics.converged`.

`cfi`, `tli`, `rmsea` and `srmr` are **expected**.

## Parameter rows: `parameters[*].sem`

`{op, lhs, rhs, free, group, label, std_all, std_lv}`, in lavaan's parameter-table terms:
`=~` loading, `~` regression, `~~` (co)variance, `~1` intercept, `:=` defined parameter, `|`
threshold. `free: false` marks fixed parameters (marker loadings, fixed variances), which have
no standard error.

`term` stays verbatim. semopy writes a loading as `x2 ~ visual` (indicator `~` factor); its
`sem` object is `{op: "=~", lhs: "visual", rhs: "x2"}`. Stata names parameters
`equation:column` in `e(b)`.

## Options that change the numbers

| Option | lavaan | semopy | Stata `sem` |
|---|---|---|---|
| `method` | `estimator = "ML"` | `obj = "MLW"` (Wishart) | `method(ml)` |
| `likelihood` (N or N − 1 in χ²) | `"normal"` (N), unless `mimic` EQS/LISREL | Wishart | |
| `missing` | `"listwise"` (`"ml"` = FIML) | `obj = "FIML"` | `method(mlmv)` |
| `information` | `"expected"` (`"observed"` with FIML) | `"expected"` | observed (`vce(oim)`) |
| `test` | `"standard"`; Satorra-Bentler, Yuan-Bentler, scaled-shifted, ... | | `vce(sbentler)` |
| `mimic` | `"lavaan"`, `"Mplus"`, `"EQS"`, `"LISREL"` | | |
| `std_lv` | `std.lv = FALSE` (marker loadings) | marker loadings | marker loadings |
| `optimizer` | `nlminb` | `SLSQP` | `technique()` |

With complete data, ML and Wishart ML give the same estimates; their χ² and SEs differ by
N / (N − 1) where the tool uses one or the other. A scaled or robust χ² (and CFI, TLI, RMSEA
built from it) is recorded as `{value, definition}` or under lavaan's `.scaled` / `.robust`
names.

## Metrics

| Name | lavaan `fitMeasures()` | semopy `calc_stats()` | Stata |
|---|---|---|---|
| `nobs` | `nobs()` | rows | `e(N)` |
| `npar` | `npar` | `len(param_vals)` | |
| `chisq`, `chisq_df`, `chisq_p` | `chisq`, `df`, `pvalue` | `chi2`, `DoF`, `chi2 p-value` | `e(chi2_ms)`, `e(df_ms)`, `e(p_ms)` |
| `chisq_baseline`, `chisq_baseline_df` | `baseline.chisq`, `baseline.df` | `chi2 Baseline`, `DoF Baseline` | `e(chi2_bs)`, `e(df_bs)` |
| `cfi`, `tli` | `cfi`, `tli` | `CFI`, `TLI` | `estat gof`: `r(cfi)`, `r(tli)` |
| `rmsea`, `rmsea_ci_low`, `rmsea_ci_high`, `rmsea_pclose` | `rmsea`, `rmsea.ci.lower`, `rmsea.ci.upper`, `rmsea.pvalue` | `RMSEA` | `r(rmsea)`, `r(lb90_rmsea)`, `r(ub90_rmsea)`, `r(pclose)` |
| `srmr` | `srmr` | — | `r(srmr)` |
| `gfi` | `gfi` | `GFI` | |
| `log_lik`, `log_lik_saturated` | `logl`, `unrestricted.logl` | — (see below) | `e(ll)` |
| `aic`, `bic` | `aic`, `bic` | — (see below) | `r(aic)`, `r(bic)` |
| `n_groups` | `lavInspect("ngroups")` | | `e(N_groups)` |

semopy's `calc_stats` reports `LogLik`, `AIC` and `BIC` built from its fit objective (for
the example below, `LogLik` is 0.283; the normal-theory log-likelihood lavaan reports is −3737.7). They aren't comparable with
other tools' log-likelihoods: writers leave them out or record them as `{value, definition}`.
semopy has no SRMR; a writer can compute it from the sample and implied covariances and say
so.

## `structures`

- `vcov` of the free parameters, `type` `expected_information`, `observed_information`,
  `robust_sem`, `robust_huber_white` or `bootstrap` (lavaan `se`, semopy `information`, Stata
  `e(vce)`).
- `numerics.converged`: lavaan `lavInspect("converged")`, semopy's fit result ("Optimization
  successful"), Stata `e(converged)`.

## Example

[`schema/examples/sem.estimation.json`](../../schema/examples/sem.estimation.json): a real
semopy fit of the three-factor Holzinger-Swineford CFA. It matches lavaan's `cfa()` of the
same model (χ² 85.31 on 24 df, CFI 0.931, TLI 0.896, RMSEA 0.092, SRMR 0.065).

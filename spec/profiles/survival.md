# Profile `survival/0.1`

Status: draft. Schema: [`schema/profiles/survival-0.1.json`](../../schema/profiles/survival-0.1.json).
Kind: standard. Builds on the core only.

Time-to-event regression: Cox proportional hazards, parametric models (AFT or PH metric), and
Fine-Gray competing risks. Surveyed 2026-10-25: from source, R survival 3.8-13 (therneau/survival
@ b76de62: `coxph`, `survreg`, `cox.zph`, `concordance`), lifelines 0.30.3, scikit-survival
0.28.0, statsmodels 0.15 `PHReg` and R cmprsk 2.2-12 `crr` (cran/cmprsk); Stata `stcox`,
`streg`, `stcrreg`, `estat concordance` and `estat phtest` from their help files. Multi-state
models, frailty and Bayesian survival were not surveyed.

## Requirements

- `meta.estimator.method`: `cox`, `parametric`, `fine_gray`, `cause_specific_cox`,
  `piecewise_exponential`, `aalen_additive`.
- `specification.survival` with `time` and `event`.
- `estimate` and `std_error` on every row that isn't dropped.
- `metrics.nobs` and `metrics.n_events`.
- A default vcov with `type`.

Conditional requirements:

- Cox and Fine-Gray (`cox`, `fine_gray`, `cause_specific_cox`): `specification.options.ties`.
- `parametric`: `meta.estimator.distribution` and `metric` (`aft` or `ph`).
- `fine_gray`: `specification.survival.competing_event_codes`.

Rows are on the estimation scale (log hazard, or log time for AFT models) unless they set the
core's `scale: "exponentiated"` with `measure: "hazard_ratio"` (or `subhazard_ratio` for
Fine-Gray).

Stata's `stcrreg` has no `ties()` option, and its help file doesn't say how tied times are
handled, so a writer fills `ties` from the manual's methods section rather than from `e()`. `stcrreg` always reports robust standard errors (`vce(robust)`, or
`vce(cluster` *id*`)` with multiple records per subject) and displays subhazard ratios unless
`noshr` is given.

## Defaults that change results

| | R `coxph` | lifelines | Stata `stcox` | statsmodels `PHReg` | scikit-survival |
|---|---|---|---|---|---|
| `ties` | **efron** | **efron** (fixed) | **breslow** (`efron`, `exactm`, `exactp`) | **breslow** (`efron`) | **breslow** (`efron`) |
| PH test `transform` | `cox.zph`: **km** | `proportional_hazard_test`: **rank** | `estat phtest`: analysis time | | |
| Concordance | Harrell (`timewt = "n"`) | Harrell | Harrell (`gheller`) | | Harrell; Uno (`concordance_index_ipcw`) |

The same Cox model gives slightly different coefficients under Efron and Breslow ties, and the
same fit gives different proportional-hazards test statistics under different time transforms.
`ties` is required; `ph_test.transform` is required whenever `ph_test` is given.

**Parametric metric.** `survreg` and lifelines' `*AFTFitter` report the AFT metric; Stata's
`streg` reports Weibull, exponential and Gompertz models in the PH metric unless `time` is
given (lognormal, loglogistic and gamma are AFT). For a Weibull, β_PH = −β_AFT / σ, so the two
metrics differ in sign and scale; `metric` says which one the rows use (`streg` stores it in
`e(frm2)`: `hazard` or `time`), and `metrics.scale` / `shape` hold the ancillary parameter
(`e(aux_p)` for Weibull, `e(gamma)` for Gompertz and loglogistic, `e(sigma)` and `e(kappa)` for
lognormal and generalized gamma).

**Identifying the Stata command.** `stcox` stores `e(cmd)` as `cox` (`stcox_fr` with
`shared()`), and `streg` stores the model's name (for example `weibull`); `e(cmd2)`
holds `stcox` or `streg`. Both display hazard ratios unless `nohr` is given, while `e(b)` stays
on the coefficient scale.

## `specification.survival`

| Name | R | Stata `stset` | lifelines | statsmodels |
|---|---|---|---|---|
| `time` | `Surv(time, ...)` | timevar | `duration_col` | `endog` |
| `start` | `Surv(start, stop, ...)` | `enter()`, `origin()` | `entry_col` | `entry` |
| `event`, `event_codes` | `Surv(..., event)` | `failure(var==codes)` | `event_col` | `status` |
| `competing_event_codes` | cmprsk `failcode`/`cencode`; `finegray()` | `stcrreg, compete()`; `e(N_compete)` | | |
| `id` | `id` | `id()` | `id_col` | |
| `strata` | `strata()` | `strata()` | `strata` | `strata` |
| `time_varying` | `tt()` | `tvc()`, `texp()` | `CoxTimeVaryingFitter` | |

## Metrics and structures

| Name | R | Stata | lifelines | statsmodels |
|---|---|---|---|---|
| `nobs` | `n` | `e(N)` | `_n_examples` | `nobs` |
| `n_events` | `nevent` | `e(N_fail)` | `event_observed.sum()` | |
| `n_subjects` | | `e(N_sub)` | | |
| `time_at_risk` | | `e(risk)` | | |
| `log_lik`, `log_lik_null` | `loglik[2]`, `loglik[1]` | `e(ll)`, `e(ll_0)` | `log_likelihood_` | `llf` |
| `lr_test` | `logtest` | `e(chi2)` (LR) | `log_likelihood_ratio_test()` | |
| `concordance` | `concordance` | `estat concordance`: `r(C)` (Harrell), `r(K)` (`gheller`) | `concordance_index_` | |
| `aic` (partial) | `AIC()` | `estat ic` | `AIC_partial_` | |
| vcov `type` | `var` (`oim`; robust with `cluster()`, model-based in `naive.var`) | `e(vce)` | `variance_matrix_` (`robust=True`) | `cov_params()` |

`structures.ph_test` is `{kind: "object", transform, global, per_term}`, each test
`{statistic, df, p_value}` (`cox.zph` table; Stata `estat phtest` `r(chi2)`, `r(df)`, `r(p)`,
and `detail` per term in the `r(phtest)` matrix). `estat phtest` tests against analysis time
unless `log`, `km`, `rank` or `time()` is given.

Convergence: Stata stores `e(converged)`; `coxph` and lifelines only warn.

## Examples

Both real runs on the Rossi recidivism data (432 released prisoners, 114 arrests):

- [`schema/examples/survival-cox-efron.estimation.json`](../../schema/examples/survival-cox-efron.estimation.json):
  lifelines `CoxPHFitter` (Efron), with concordance and a rank-transform PH test. Matches R's
  `coxph`.
- [`schema/examples/survival-cox-breslow.estimation.json`](../../schema/examples/survival-cox-breslow.estimation.json):
  statsmodels `PHReg` with its default Breslow ties, for comparison (`fin` −0.3790 vs −0.3794).

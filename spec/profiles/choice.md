# Profile `choice/0.1`

Status: draft. Schema: [`schema/profiles/choice-0.1.json`](../../schema/profiles/choice-0.1.json).
Kind: standard. Builds on the core only.

Discrete-choice models: multinomial (conditional) logit with alternative attributes, mixed
(random-parameters) logit, nested and latent-class logit, in preference or willingness-to-pay
space. Surveyed 2026-10-25 from source: R mlogit 2.0-0 (cran/mlogit @ 9299242), logitr 1.2.0
(jhelvy/logitr @ e375a1d), apollo 0.3.9 (cran/apollo @ 82ef716), Python xlogit 0.2.7
(arteagac/xlogit @ c3d6d44) and Biogeme (michelbierlaire/biogeme @ 8d1063b). Stata
`cmclogit`, `cmmixlogit` and `cmmprobit` are mapped from their help files; the user-written
`mixlogit` from its documentation, defaults not checked. gmnl, Bayesian (HB) estimation and
rank-ordered models (`cmrologit`, whose `ties()` default is `exactm`, and `cmroprobit`) were not
surveyed.

A plain MNL on choice-situation groups is the same likelihood as
[`conditional-logit/0.1`](conditional-logit.md); a writer that fills both can claim both.

## Requirements

- `meta.estimator.method`: `mnl`, `mixed_logit`, `nested_logit`, `cross_nested_logit`,
  `latent_class_logit`, `gmnl`, `probit`, `hybrid`.
- `specification.choice` with `case` (choice-situation id) and `alternative`.
- `estimate` and `std_error` on every row that isn't dropped.
- `metrics.n_cases` and `metrics.log_lik`.
- A default vcov with `type`.
- `structures.numerics.converged`.

For a simulated model (`mixed_logit`, `gmnl`), also:

- `specification.choice.random_parameters` (`[{term, distribution}]`),
- `specification.choice.simulation` (`draws` and `type`, plus `seed`, `burn`),
- `specification.choice.panel`: draws per decision maker or per choice situation,
- at least one row with `choice.role` `sd`, `chol` or `spread`.

`metrics.n_decision_makers` is **expected**.

## Defaults that change results

| | mlogit | logitr | apollo | xlogit | Biogeme | Stata `cmmixlogit` |
|---|---|---|---|---|---|---|
| Draws | `R = 40` | `numDraws = 500` | `interNDraws` (user) | `n_draws = 1000` | `number_of_draws = 10000` | 500 + ⌊2.5 √(N_case (ln(r + 5) + v))⌋, grows with the sample |
| Draw type | pseudo-random (`halton = NULL`; `NA` for Halton) | `"sobol"` | `"mlhs"` | Halton | set in the expression (`NORMAL_HALTON2`, ...) | Hammersley |
| Seed | `seed = 10` | | `apollo_control$seed` | `random_state` | `seed = 0`: a new seed each run | needed only with `intmethod(random)` |
| Optimizer | `"bfgs"` (`"nr"` for plain MNL) | nloptr L-BFGS | `"bgw"`, `maxIterations = 200` | scipy `"BFGS"` | `optimization_algorithm` | `nr` (`cmmprobit`: `bfgs`) |
| Reported SEs | Hessian | Hessian (`robust = TRUE`) | `se` and `robse` | see below | robust in the default table | OIM; `vce(robust)` clusters on the case |

xlogit's `MixedLogit` reports by default the BFGS optimizer's approximation of the inverse
Hessian as the vcov (`num_hess=False`); `MultinomialLogit` computes a numerical Hessian. Record
the first as `type: "bfgs_approx"`: its standard errors can differ noticeably from a Hessian's.
xlogit's p-values use a t distribution with df = number of choice situations.

Because Biogeme's default seed changes every run, a simulated Biogeme result is reproducible
only if the record has the seed actually used. Stata's default number of points depends on the
number of cases and parameters (r random coefficients, v variance parameters), so record
`e(intpoints)` rather than the option. Default base alternatives differ too: the most often
chosen in `cmclogit` and `cmmixlogit`, the first in sort order in `cmmprobit` (which also
normalizes scale on the second).

## `specification.choice`

| Name | Meaning | Stata `cm*` | mlogit | logitr | apollo | xlogit |
|---|---|---|---|---|---|---|
| `case` | choice situation | `cmset` caseid, `e(caseid)` | `dfidx` chid | `obsID` | one row per case | `ids` |
| `alternative` | alternative id | `e(altvar)` | `dfidx` alt | (long data) | wide | `alts` |
| `decision_maker` | individual | `cmset` panelvar | `dfidx` id | `panelID` | `indivID` | `panels` |
| `panel` | draws per individual | `cmxtmixlogit` | `panel` | `panelID` given | `panelData` | `panels` given |
| `base_alternative` | normalized constant | `basealternative()`; `e(i_base)` (`cmmixlogit`: `e(base)`) | `reflevel` | | | `base_alt` |
| `availability` | availability variable | | | | `avail` | `avail` |
| `space`, `scale_term` | WTP space and its price term | | | `scalePar` | user-coded | `scale_factor` |
| `random_parameters` | `{term, distribution}` | `random()` | `rpar` (`n`, `ln`, `cn`, `t`, `u`, `zbu`, `zbt`) | `randPars` | user-coded | `randvars` (`n`, `ln`, `t`, `tn`, `u`) |
| `correlated` | Cholesky | | `correlation` | `correlation` | user-coded | |
| `simulation` | draws, type, seed, burn | `intpoints()`, `intmethod()`, `intseed()`, `intburn()` | `R`, `halton`, `seed` | `numDraws`, `drawType` | `apollo_draws` | `n_draws`, `halton`, `random_state` |

Also `nests` (`[{name, alternatives}]`) and `n_classes`.

## Parameter rows: `parameters[*].choice`

`{role, term, terms, alternative, class, nest, distribution}` with `role` one of
`coefficient`, `asc`, `mean`, `sd`, `chol`, `spread`, `nest` (nest parameter),
`scale`, `class_share`, `wtp`. Term spellings vary (`_intercept.hiland`, `sd.feat` in
xlogit; `sd_feat` in logitr; `(Intercept):hiland` and `sd.feat` in mlogit); `choice` says what each is
without parsing.

## Metrics

| Name | Stata `cm*` | mlogit | logitr | apollo | xlogit | Biogeme |
|---|---|---|---|---|---|---|
| `nobs` | `e(N)` (rows) | choice situations | | `nObs` | `sample_size` (situations) | sample size |
| `n_cases` | `e(N_case)` | `nobs()` | `n$obs` | `nObs` | `sample_size` | observations |
| `n_decision_makers` | | | | `nIndivs` | | |
| `log_lik` | `e(ll)` | `logLik()` | `logLik` | `maximum` | `loglikelihood` | `final_loglikelihood` |
| `log_lik_null` (all zero) | | | `nullLogLik` | `LL0` | | `null_loglikelihood` |
| `log_lik_constants` (shares) | | McFadden R² base | | `LLC` | | |
| `rho2`, `adj_rho2` | | `summary()` McFadden R² (vs constants) | | vs equal shares | | `rho_square_null`, `rho_square_init`, `rho_bar_square_null` |
| `aic`, `bic` | | `AIC()` | | `AIC`, `BIC` | `aic`, `bic` | `akaike_…`, `bayesian_information_criterion` |

`nobs` means different things across tools (rows in Stata, choice situations elsewhere), so
`n_cases` is the required count. `rho2` has two common bases, equal shares and constants only;
mlogit's McFadden R² uses the second. Record `{value, definition}` when it isn't
1 − log_lik / log_lik_null. `bic`'s n is usually `n_cases`.

## `structures`

- `vcov`: `type` from `oim`, `bfgs_approx`, `opg`, `robust`, `cluster`, `bootstrap`.
  apollo reports `se` and `robse` (and `bootse`): record each, mark the default.
- `numerics.converged`: xlogit `convergence`, mlogit `est.stat$code` 1 or 2 (3 means the last
  step found no improvement), apollo `successfulEstimation`, Biogeme
  `algorithm_has_converged`, logitr `status > 0`, Stata `e(converged)`. Mixed-logit
  likelihoods have local optima, so `options.n_starts` (logitr `numMultiStarts`) is worth
  recording.

## Examples

On the yogurt scanner panel (Jain, Vilcassim and Chintagunta 1994; 2,412 choices among four
brands by 100 households), both real xlogit runs:

- [`schema/examples/choice-mnl.estimation.json`](../../schema/examples/choice-mnl.estimation.json):
  MNL with price, feature and brand constants. Matches logitr's published estimates.
- [`schema/examples/choice-mixed-logit.estimation.json`](../../schema/examples/choice-mixed-logit.estimation.json):
  the feature coefficient normal across households, 500 Halton draws per household.

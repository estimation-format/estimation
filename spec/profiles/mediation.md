# Profile `mediation/0.1`

Status: draft. Schema: [`schema/profiles/mediation-0.1.json`](../../schema/profiles/mediation-0.1.json).
Kind: standard. Builds on the core only.

Mediation analyses, whether computed from two regressions, from two-stage (instrumental-
variables) regressions, or inside an SEM. Surveyed 2026-10-25: from source, R mediation 4.5.1
(kosukeimai/mediation @ 44e1146; `mediate` and `mediate_tsls`), lavaan (defined parameters,
`:=`), pingouin 0.7.0 `mediation_analysis` and statsmodels 0.15 `Mediation`; PROCESS, Stata
`sem` / `estat teffects`, StataNow `mediate` and Stata `ivmediate` (Dippel, Ferrara and
Heblich) from documentation, which means their stored-result names still need checking against
their help files. The same layout
fits other bootstrap mediation tools (`medsem`, `indirect_boot`): a writer fills
`specification.mediation` and tags each effect row.

An SEM-based record (lavaan `:=`, Stata `sem`) claims [`sem/0.1`](sem.md) too.

## Requirements

- `specification.mediation`: `treatment`, `mediators`, `outcome`, and `inference` with its
  `method`.
- `metrics.nobs`.
- At least one row whose `mediation.effect` is an indirect effect (`indirect` or an `acme_*`).
- Every row with a `mediation` object has `estimate` and either `std_error` or
  `conf_low`/`conf_high`. R mediation reports intervals and p-values but no standard errors.

No vcov is required: bootstrap tools often report none.

## `specification.mediation`

| Name | R mediation | pingouin | statsmodels | PROCESS | lavaan / Stata sem |
|---|---|---|---|---|---|
| `treatment` | `treat` | `x` | `exposure` | `x=` | in the model |
| `mediators` | `mediator` | `m` (one or several) | `mediator` | `m=` | in the model |
| `outcome` | from `model.y` | `y` | `outcome_model` | `y=` | in the model |
| `covariates` | terms in both models | `covar` | in the models | `cov=` | in the model |
| `moderators` | | | | `w=`, `z=` | |
| `process_model` | | | | `model=` (4 = simple) | |
| `treat_value`, `control_value` | `treat.value` (1), `control.value` (0) | | | | |

`structure` is `simple`, `parallel`, `serial` or `moderated`; `models` lists how the mediator
and outcome models were fit, or is `"sem"`.

### `inference`: where the defaults differ most

| | R mediation | statsmodels | pingouin | lavaan | PROCESS | Stata `estat teffects` |
|---|---|---|---|---|---|---|
| `method` | quasi-Bayesian (`boot = FALSE`) | `"parametric"` (quasi-Bayesian) | bootstrap | delta (`se = "standard"`), or bootstrap | bootstrap | delta |
| `reps` | `sims = 1000` | `n_rep = 1000` | `n_boot = 500` | `bootstrap = 1000` | 5000 | |
| `ci_type` | `"perc"` (`"bca"`) | percentile | `bc` (bias-corrected, not accelerated) | `"perc"` in `parameterEstimates()` | percentile (v3+) | normal |
| `seed` | | `rng` | `seed = None` | | `seed=` | |

The same indirect effect gets different intervals (and different "significance") from a
Sobel/delta test, a percentile bootstrap, a bias-corrected bootstrap and a quasi-Bayesian
simulation, so `method`, `reps`, `ci_type` and `seed` are what a reader needs to compare two
results. `conf_low`/`conf_high` on effect rows are the intervals the method produced, not
estimate ± z·SE.

## Two-stage (IV) mediation

Two tools instrument part of the mediation chain; they record `instruments` and
`instrumented`:

| | `mediate_tsls` (R mediation) | `ivmediate` (Stata) |
|---|---|---|
| `instrumented` | `mediator`: the outcome model uses the mediator's first-stage fitted values | `treatment` |
| `instruments` | regressors of `model.m` that are not in `model.y` | `instrument()` |
| `models[].estimator` | `ols` (mediator), `tsls` (outcome) | IV |
| `inference.method` | `aroian` (Aroian 1947 product SE; default) or `bootstrap` (`boot = TRUE`, `sims`) | |
| Effects | `d0` = `d1` (indirect), `z0` = `z1` (direct), `tau.coef`, `n0`, each with an SE | indirect, direct, total |

`mediate_tsls` always computes its analytic SEs with `sandwich::vcovCL`; with `cluster = NULL`
each row is its own cluster (an HC1-type variance), so `robustSE` has no effect. When a tool
reports first-stage diagnostics, they go in `structures.first_stage` as in [`iv/0.1`](iv.md).

StataNow's `mediate` estimates potential-outcome effects with a model family for the mediator
and the outcome (`models[].estimator`), one or two mediators, and reports `nie` (indirect),
`nde` (direct), `te` (total), `pm` (proportion mediated) and `cde` (`controlled_direct`).

## Effect rows: `parameters[*].mediation`

`{effect, mediator, path, moderator_value}`:

| `effect` | Meaning | R mediation | statsmodels | pingouin |
|---|---|---|---|---|
| `a`, `b` | X → M, M → Y paths | (in the models) | | `M ~ X`, `Y ~ M` |
| `indirect` | a·b | | | `Indirect` |
| `acme_control`, `acme_treated`, `acme_average` | average causal mediation effects | `d0`, `d1`, `d.avg` | `ACME (control)`, ... | |
| `controlled_direct` | direct effect with the mediator fixed | | | |
| `direct`, `ade_*` | direct effect | `z0`, `z1`, `z.avg` | `ADE (...)` | `Direct` |
| `total` | total effect | `tau.coef` | `Total effect` | `Total` |
| `prop_mediated`, `prop_mediated_*` | share mediated | `n0`, `n1`, `n.avg` | `Prop. mediated (...)` | |
| `index_moderated_mediation`, `contrast` | PROCESS indices and pairwise contrasts | | | |

`mediator` names which mediator a specific indirect effect goes through; `path` lists a serial
path in order; `moderator_value` marks a conditional indirect effect.

## Example

[`schema/examples/mediation.estimation.json`](../../schema/examples/mediation.estimation.json):
a real pingouin run on the JOBS II data from R's mediation package (treatment → job-search
self-efficacy → depression), no covariates, 5000 bias-corrected bootstrap replications.

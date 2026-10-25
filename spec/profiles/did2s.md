# Profile `did2s/0.1`

Status: draft. Schema: [`schema/profiles/did2s-0.1.json`](../../schema/profiles/did2s-0.1.json).
Kind: tool. `x-extends`: [`did/0.1`](did.md), with no deviations.

Gardner's (2021) two-stage difference-in-differences as implemented by `did2s` for Stata
(`did2s.ado` 0.7, kylebutts/did2s_stata @ be5406f, 2026-10-21) and R (`did2s` 1.3.0), and by
pyfixest's `did2s` (0.60.0, ported from the R package). The first stage fits the untreated
rows' outcome (unit and time fixed effects, optionally covariates); the second stage regresses
the residualized outcome on the treatment terms, with a GMM variance that accounts for the
first stage.

## Requirements

Everything `did/0.1` requires (the profile includes its rules), plus:

- `meta.estimator.method: "did2s"`.
- `specification.did.treatment`, and `comparison: "untreated"`: the first stage uses every
  untreated observation.
- `specification.options.first_stage` and `second_stage`, as written.
- `specification.clusters`: all three implementations require a cluster variable.
- A vcov of type `two_stage_gmm` or `cluster_bootstrap` that names its `cluster`.

R and pyfixest return a fixest / pyfixest fit, with p-values and a residual df: their records
meet `inference/0.1` and SHOULD claim it. Stata `did2s` posts `e(b)` and `e(V)` without
`dof()`, so inference is normal and there is no `df_residual`: its records claim `did/0.1`
and `did2s/0.1` only.

## What each implementation stores

| Name | Stata `did2s` | R `did2s` | pyfixest |
|---|---|---|---|
| `specification.did.treatment` | `treatment()` | `treatment` | built as `is_treated` from `gname` |
| `specification.clusters` | `cluster()`, `e(clustvar)` | `cluster_var` | `cluster` |
| `options.first_stage` | `first_stage()`, `absorb()`, `unit()` | `first_stage` | `first_stage` (or from `idname`, `tname`, `xfml`) |
| `options.absorbed` | `e(absorb)`: plain `i.x` factors in `first_stage()` are absorbed | | |
| `options.second_stage` | `second_stage()` | `second_stage` | `second_stage` |
| `options.tolerance`, `max_iterations` | `tolerance()` (1e-12), `maxiter()` (2000): preconditioned CG for the first stage and the variance | `vcov_tol` (1e-10), `vcov_maxiter` (2000) | |
| `options.vcov_method`, `bootstrap` | | `vcov_method` (`sparse`, `matrix_free`), `bootstrap`, `n_bootstraps` | |
| `metrics.nobs` | `e(N)` | `nobs()` | `_N` |
| `metrics.n_not_identified` | `e(N_noid)`: rows in a FE level with no untreated rows, dropped | | |
| `metrics.df_residual` | none | `df.residual()` | `_dfd` |
| `structures.numerics.converged` | `e(converged)` | | |
| vcov `type` | `two_stage_gmm` | `two_stage_gmm`, or `cluster_bootstrap` | `two_stage_gmm` (`_vcov_type_detail` `"CRV1 (GMM)"`) |
| vcov `ssc` | none: `bread · meat · bread` | none: `crossprod(IF)` passed to `summary(vcov =)` | none (see below) |
| vcov `df_t` | none (z) | `fixest::degrees_freedom(x, "t")` | `_df_t` (N − K) |

pyfixest 0.60.0 replaces the vcov after fitting the second stage with `vcov="iid"`, and the
iid fit's `_ssc` ((N−1)/(N−K)) stays on the object without being applied. Writers record
`ssc.formula: "none"`, not `_ssc`.

## Parameter rows

The second stage is user-specified, so writers set `did` per row from its terms: relative-time
dummies are `{type: "event", event_time}` (`binned: true` for pooled endpoints), a single
treatment dummy is `{type: "simple"}`, and anything else (covariates, heterogeneity terms)
has no `did` or `type: "other"`. Term spellings: R `rel_year::-2`; pyfixest `rel_year::-2.0`
(float levels when the variable is float); Stata factor-variable names such as `18.ry`.
Stata factor levels can't be negative, so Stata users shift event time into a new variable:
writers record `event_time` on the original scale, not the shifted level.

## Example

[`schema/examples/did2s.estimation.json`](../../schema/examples/did2s.estimation.json): pyfixest
0.60.0 on `df_het` (46,500 rows, 1,500 units, 40 state clusters), event times −5…5 with
binned endpoints.

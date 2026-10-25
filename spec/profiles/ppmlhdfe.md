# Profile `ppmlhdfe/0.1`

Status: draft. Schema: [`schema/profiles/ppmlhdfe-0.1.json`](../../schema/profiles/ppmlhdfe-0.1.json).
Kind: tool. `x-extends`: [`glm/0.1`](glm.md), with no deviations.

Records of Stata `ppmlhdfe` (Correia, Guimarães and Zylkin), Poisson pseudo-maximum likelihood
with high-dimensional fixed effects, surveyed from `ppmlhdfe.ado` 2.3.4 and `ppmlhdfe.mata`
(sergiocorreia/ppmlhdfe @ b85665d). ppmlhdfe partials out the fixed effects with reghdfe, so
many of its `e()` names are reghdfe's.

## Requirements

Everything `glm/0.1` requires (the profile includes its rules), plus:

- `meta.estimator`: `distribution: "poisson"`, `link: "log"`.
- `metrics.n_separated` (`e(num_separated)`) and `n_singletons` (`e(num_singletons)`).
- `specification.options.separation` (`e(separation)` as a list) and `drop_singletons`
  (`e(drop_singletons)`).
- `structures.fixed_effects`, one `{name, levels}` per absorbed fixed effect (from
  `e(absvars)`, `e(extended_absvars)` and `e(dof_table)`). With `noabsorb`, ppmlhdfe absorbs
  `_cons`.

The fixed-effect fields use [`linear-fe/0.1`](linear-fe.md)'s names; the profile doesn't claim
`linear-fe`, which is for linear models.

## Stored results

| ppmlhdfe | Record |
|---|---|
| `e(N)`, `e(N_full)` | `metrics.nobs`, `nobs_full` (= N + singletons + separated) |
| `e(num_singletons)`, `e(num_separated)` | `metrics.n_singletons`, `n_separated`; also `specification.sample.dropped` |
| `e(df)` | `metrics.df_residual` (ppmlhdfe uses `e(df)`, as `glm` does, not `e(df_r)`) |
| `e(df_m)`, `e(df_a)` | `metrics.df_model`, `df_absorbed` |
| `e(ll)`, `e(deviance)` | `metrics.log_lik`, `deviance` |
| `e(ll_0)` | `metrics.log_lik_fe_only`: the FE-only model, not a constant-only one |
| `e(r2_p)` | `metrics.pseudo_r2` as `{value, definition: "1 - ll/ll_0, ll_0 FE-only"}` |
| `e(chi2)`, `e(chi2type)` | `metrics.chi2` (Wald) |
| `e(separation)` | `options.separation`: default `["fe", "simplex", "relu"]`; `separation(all)` adds `mu`; `none` is `[]`; `ir` is recorded as `relu` |
| `tolerance()`, `itolerance()`, `maxiterations()`, `guess()` | `options.tolerance` (1e-8), `inner_tolerance`, `max_iterations` (10000), `guess` (`simple`) |
| `e(ic)`, `e(ic2)`, `e(converged)` | `structures.numerics.iterations`, `inner_iterations`, `converged` |
| `e(vce)`, `e(clustvar)`, `e(N_clust)` | vcov `type`, `cluster`, `n_clusters` |
| `e(offset)` | `specification.offset` (`exposure: true` with `exposure()`) |

`e(converged)` is always 1 in a posted result: ppmlhdfe stops with an error instead of
posting an unconverged fit.

## Variance

ppmlhdfe calls reghdfe's solver in its asymptotic mode: N/(N−1) for robust, G/(G−1) for
cluster, no (N−1)/(N−K), and z tests (no `df_t`). Record
`ssc: {convention: "ppmlhdfe", formula: "G/(G-1)", factors: {...}}`. This is the usual reason
ppmlhdfe and fixest `fepois` standard errors differ while their estimates agree.

## Example

[`schema/examples/ppmlhdfe.estimation.json`](../../schema/examples/ppmlhdfe.estimation.json):
`ppmlhdfe Y X1 X2, absorb(f1 f2) vce(cluster f1)`. A shape example: the values were computed
with pyfixest `fepois` and ppmlhdfe's cluster adjustment, not by Stata.

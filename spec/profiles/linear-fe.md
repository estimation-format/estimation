# Profile `linear-fe/0.1`

Status: draft. Schema: [`schema/profiles/linear-fe-0.1.json`](../../schema/profiles/linear-fe-0.1.json).
Kind: standard. Builds on [`inference/0.1`](inference.md).

Linear models with absorbed fixed effects. Surveyed (documentation or source checked
2026-10-24): fixest 0.14.2 and lfe (R); pyfixest 0.60.0 and linearmodels (Python); reghdfe
6, `areg` and `xtreg` in StataNow 19 (Stata); FixedEffectModels.jl (Julia).

## Requirements

Everything `inference/0.1` requires, plus:

- `metrics.n_singletons`: singleton rows dropped (0 when none were);
- `specification.options.drop_singletons`: whether singletons were dropped;
- `structures.fixed_effects`: one entry per fixed effect, each with `name` and `levels`.

Why singletons are required: `nobs` means different samples in different tools. reghdfe,
fixest (`fixef.rm = "perfect_fit"`), pyfixest (`fixef_rm = "singleton"`) and
FixedEffectModels.jl (`drop_singletons = true`) drop singletons by default; lfe documents no
singleton removal. Requiring `nobs`, `n_singletons` and `drop_singletons` together makes the
difference visible.

Not required, though in the vocabulary: `r2_within` (`areg` reports none), and convergence
(`iterations`, `converged`), which several tools don't report by default.

## Metrics

| Name | Meaning | fixest | reghdfe | linearmodels | others |
|---|---|---|---|---|---|
| ✓ `nobs` | rows used | `nobs` | `e(N)` | `nobs` | pyfixest `_N`; lfe `N`; areg/xtreg `e(N)`; FEM.jl `nobs` |
| `nobs_full` | rows used plus singleton rows dropped | — (`nobs_origin` counts rows before subset, NA and singleton removal: `specification.sample.rows_input`) | `e(N_full)` | — | |
| ✓ `n_singletons` | singleton rows dropped | not stored separately | `e(num_singletons)` | — | pyfixest: a warning only; areg/xtreg `e(ksingle)` (per absorbed variable) |
| ✓ `df_residual` | residual df as the tool reports it | `df.residual`* | `e(df_r)` | `df_resid` | areg/xtreg `e(df_r)`; FEM.jl `dof_residual` (min(G) − 1 under clustering); pyfixest `_dfd` (min(G) − 1 under clustering) |
| `df_model` | model df | | `e(df_m)` | `df_model` | areg/xtreg `e(df_m)`; FEM.jl `dof` |
| `df_absorbed` | df lost to the fixed effects | | `e(df_a)` | | areg `e(df_a)`, `e(dfabsorb)`; xtreg `e(df_a)`; FEM.jl `dof_fes` |
| `df_absorbed_nested` | fixed-effect df redundant because nested in a cluster | | `e(df_a_nested)` | | |
| `rss`, `tss`, `tss_within` | sums of squares | `ssr`*, `ssr_null`, `ssr_fe_only` | `e(rss)`, `e(tss)` | `resid_ss`, `total_ss`, `model_ss` | areg/xtreg `e(rss)`, `e(mss)`; xtreg `e(tss)`; FEM.jl `rss`, `tss`; lfe `P.TSS` |
| `r2`, `adj_r2` | R² | `r2()` | `e(r2)`, `e(r2_a)` | `rsquared` | areg/xtreg `e(r2)`, `e(r2_a)`; lfe `r2`, `r2adj`; pyfixest `_r2`, `_adj_r2`; FEM.jl `r2()`, `adjr2()` |
| `r2_within`, `adj_r2_within` | within R² | `r2(, "wr2")` | `e(r2_within)`, `e(r2_a_within)` | `rsquared_within` | xtreg `e(r2_w)`; pyfixest `_r2_within`, `_adj_r2_within`; FEM.jl `r2_within`; areg: none |
| `r2_between`, `r2_overall` | panel R²s | | | `rsquared_between`, `rsquared_overall` | xtreg `e(r2_b)`, `e(r2_o)` |
| `r2_inclusive` | R² including the fit of the fixed effects | | | `rsquared_inclusive` | |
| `sq_corr_fitted` | squared corr(y, ŷ) | `sq.cor` | | `corr_squared_*` | |
| `sigma` | root mean squared error | `sigma()` | `e(rmse)` | `s2` (variance) | areg/xtreg `e(rmse)`; xtreg `e(sigma_e)`; pyfixest `_rmse`; lfe `rse` |
| `sigma_fe`, `rho` | fixed-effect SD; share of variance due to the fixed effects | | | `variance_decomposition` | xtreg `e(sigma_u)`, `e(rho)` |
| `log_lik`, `log_lik_fe_only`, `log_lik_null` | log-likelihoods | `loglik`, `ll_fe_only`, `ll_null` | `e(ll)`, `e(ll_0)` | `loglik` | areg/xtreg `e(ll)`, `e(ll_0)`; FEM.jl `loglikelihood()` |
| `f_stat`, `f_stat_robust` | joint test of the regressors | `fitstat` | `e(F)` | `f_statistic`, `f_statistic_robust` | areg/xtreg `e(F)`; pyfixest `_f_statistic`; lfe `fstat`, `P.fstat`; FEM.jl `F` |
| `f_fe` | test that the fixed effects are jointly zero | | | `f_pooled` | xtreg `e(F_f)`; areg `e(F_absorb)` |
| `sum_weights` | sum of weights | | `e(sumweights)` | | |
| `rank` | rank of the vcov | | `e(rank)` | | areg/xtreg `e(rank)` |

✓ required. \* a method or derived value (`r2()`, `fitstat()`, `sigma()`), not a stored
element.

## Structures

**`fixed_effects`**, one entry per fixed effect: `name`; `components` (for interactions and
slopes, as reghdfe `e(extended_absvars)`); `levels` (fixest `fixef_sizes`) and
`levels_in_data`; `redundant` and `redundant_method` (reghdfe `e(dof_table)`: exact for
nested fixed effects, `pairwise`, `firstpair`, `clusters`, `continuous`); `nested_in`
(clusters, other fixed effects); `group_size` `{min, mean, max}` (linearmodels
`entity_info`/`time_info`, xtreg `e(g_min)`, `e(g_avg)`, `e(g_max)`); `constant_reported`
(reghdfe `e(report_constant)`).

**`numerics`**: `iterative`; `algorithm` (reghdfe `technique()`: map, lsmr, lsqr; fixest
`fixef.algo`; areg/xtreg `e(apm)`: halperin, cimmino; pyfixest `demeaner`); `acceleration`
(reghdfe: cg, sd, aitken, none); `transform` (reghdfe: symmetric_kaczmarz, kaczmarz,
cimmino); `preconditioner`; `tolerance` (fixest `fixef.tol`, reghdfe `tolerance()`, pyfixest
`fixef_tol`, FEM.jl `tol`, Stata `tolerance()`); `max_iterations` (fixest `fixef.iter`,
reghdfe `iterations()`, pyfixest `fixef_maxiter`, FEM.jl `maxiter`, Stata `iterate()`);
`iterations` (reghdfe `e(ic)`, FEM.jl `iterations`); `converged` (reghdfe `e(converged)`,
FEM.jl `converged`, areg/xtreg `e(converged)`); `collinearity_tolerance` (fixest
`collin.tol`, pyfixest `collin_tol`); `collinear_terms` (fixest `collin.var`);
`collinearity_min_norm` (fixest `collin.min_norm`).

**`vcov`**: `type` (mapped to fixest `vcov=`, reghdfe `vce()`, linearmodels `cov_type`);
`cluster`; `n_clusters` per variable (reghdfe `e(clust#)`) and `n_clusters_min`
(`e(N_clust)`); `ssc` with every factor the tool has: fixest `ssc()` (`K.adj`, `K.fixef`,
`G.adj`, `G.df`, `t.df`, `K.exact`); pyfixest `ssc()` (`k_adj`, `k_fixef`, `G_adj`, `G_df`;
resolved values in `_ssc_dict`); reghdfe `e(dofmethod)`; FEM.jl (no options: a fixed effect
nested in a cluster counts 1 in `dof_fes`).

## Options

`specification.options` uses these names, with each tool's default:

| Option | fixest | pyfixest | reghdfe | FEM.jl | Stata areg/xtreg (several absorbed) | lfe |
|---|---|---|---|---|---|---|
| `drop_singletons` | yes (`fixef.rm = "perfect_fit"`) | yes (`fixef_rm = "singleton"`) | yes (`keepsingletons` off) | `true` | not checked (reports `e(ksingle)`) | no removal documented |
| `tolerance` | `fixef.tol` 1e-6 | `fixef_tol` 1e-6 | 1e-8 | `tol` 1e-6 | `tolerance(1e-8)` | |
| `max_iterations` | `fixef.iter` 10,000 | `fixef_maxiter` 10,000 | 16,000 | `maxiter` 10,000 | `iterate(50)` | |
| `collinearity_tolerance` | `collin.tol` 1e-9 | `collin_tol` 1e-9 | | | | |
| `threads` | `nthreads` | | `parallel()` | `nthreads` | | |
| weights type | | `weights_type` (`"aweights"`) | `[aw]`, `[fw]`, `[pw]` | | | |
| other | | | | | `apcriterion(max)` | `exactDOF = FALSE`, `cmethod = "cgm"` |

## Sample

reghdfe `e(sample)` and fixest `obs_selection` mark the rows used. The record holds the
counts above and, as an attachment or a hash, the rows themselves.

# Profile `iv/0.1`

Status: draft. Schema: [`schema/profiles/iv-0.1.json`](../../schema/profiles/iv-0.1.json).
Kind: standard. Builds on [`inference/0.1`](inference.md).

Instrumental-variables models. Surveyed (2026-10-24): StataNow 19 `ivregress` and its
postestimation; ivreg2 / ivreghdfe 1.1.4 (which keeps ivreg2's `e()` names); fixest 0.14.2;
R `ivreg`; estimatr `iv_robust`; lfe; linearmodels 7.1; pyfixest 0.60.0;
FixedEffectModels.jl.

## Requirements

Everything `inference/0.1` requires, plus `specification.endogenous` and
`specification.instruments` (the excluded instruments).

A `first_stage` test in `tests` is **expected**, not required: most tools compute first-stage
statistics only on request. Writers SHOULD include it when the tool computed it, and
validators warn when no `first_stage` test is present.

## What each tool stores

| Tool | Endogenous / instruments | First-stage statistics by default | On request |
|---|---|---|---|
| Stata `ivregress` | `e(endog)`, `e(exog)` | none | `estat firststage`: R², partial R², F per endogenous, Shea, minimum eigenvalue; `estat endogenous`: Durbin, Wu, score; `estat overid`: Sargan, Basmann, score, Hansen J |
| ivreg2 / ivreghdfe | `e(instd)`, `e(insts)`, `e(exexog)` | underidentification `e(idstat)`; weak ID `e(widstat)`, `e(cdf)`, `e(rkf)`; `e(j)` | `first`/`ffirst`: matrix `e(first)` per endogenous (`F`, `pr2`, `sheapr2`, `SWF`, `APF`, ...), `e(arf)`, `e(sstat)`; `endog()`: `e(estat)` |
| fixest `feols` IV | `iv_endo_names`, `iv_inst_names_xpd`, `iv_first_stage` | `iv_wh` (Wu-Hausman), `iv_sargan` | `fitstat`: `ivf`, `ivwald`, `cd`, `kpr`, `wh`, `sargan` |
| R `ivreg` | `endogenous`, `instruments` | `summary()`: weak-instruments F per endogenous, Wu-Hausman, Sargan | — |
| estimatr `iv_robust` | `terms_regressors` | none | `diagnostics = TRUE` (not with fixed effects) |
| lfe `felm` IV | `endovars`, `stage1$instruments` | `stage1$iv1fstat`, `stage1$rob.iv1fstat` | `condfstat()` (Sanderson-Windmeijer) |
| linearmodels | `endog`, `instruments` | none (computed on access) | `first_stage.diagnostics`, Cragg-Donald, Kleibergen-Paap, Sargan, Basmann, Wooldridge, Anderson-Rubin, Wu-Hausman, Durbin |
| pyfixest IV | `_endogvar`, `_non_exo_instruments` | `_f_stat_1st_stage` | `IV_Diag()`: `_eff_F` (Montiel Olea-Pflueger) |
| FixedEffectModels.jl | formula | `F_kp`, `p_kp` (Kleibergen-Paap) | — |

## Tests

IV tests go in `tests` (core 4.8), one object per test, with the `category` and `name` below.
A first-stage test names its equation as `parameters` do: `component: "first_stage"`,
`response` = the endogenous variable. Tools report several versions of the overidentification
and endogeneity tests, so a record may hold more than one of each.

| `category` | `name` | Meaning | Stata `ivregress` | ivreg2 / ivreghdfe | fixest | R `ivreg` / estimatr / lfe | linearmodels | pyfixest / FEM.jl |
|---|---|---|---|---|---|---|---|---|
| `first_stage` | `f`, `wald` (robust) | first-stage F of the excluded instruments | `estat firststage` F | `e(first)` `F` | `ivf1`; `ivwald1` (robust) | weak-instruments F; `diagnostic_first_stage_fstatistic`; `iv1fstat` | `f.stat` | `_f_stat_1st_stage` |
| `first_stage` | `sanderson_windmeijer_f`, `angrist_pischke_f` | conditional F per endogenous regressor | | `e(first)` `SWF`, `APF` | | lfe `condfstat` | | |
| `first_stage` | `effective_f` | Montiel Olea-Pflueger effective F | | | | | | pyfixest `_eff_F` |
| `underidentification` | `anderson_lm`, `kleibergen_paap_rk_lm`, `kleibergen_paap_rk` | rank test of the first stage | | `e(idstat)`, `e(idp)`, `e(iddf)` | `kpr`* | | | |
| `weak_identification` | `cragg_donald_f` | Cragg-Donald Wald F (no p-value) | minimum eigenvalue statistic | `e(cdf)` | `cd` | | `cragg_donald_f` | |
| `weak_identification` | `kleibergen_paap_rk_wald_f` | Kleibergen-Paap rk Wald F (no p-value) | | `e(rkf)` | | | `kleibergen_paap_f` | FEM.jl `F_kp`, `p_kp` |
| `weak_identification` | `anderson_rubin`, `stock_wright` | weak-instrument-robust tests of the endogenous coefficients | | `e(arf)`, `e(archi2)`; `e(sstat)` | | | | |
| `overidentification` | `sargan`, `basmann`, `score`, `hansen_j`, `anderson_rubin` (LIML) | overidentifying restrictions | `estat overid` | `e(j)`, `e(sargan)` | `iv_sargan` | Sargan; `diagnostic_overid_test` | `sargan`, `basmann`, `anderson_rubin`, `wooldridge_overid` | |
| `endogeneity` | `durbin`, `wu_hausman`, `score`, `c` | exogeneity of the endogenous regressors | `estat endogenous` | `e(estat)` | `iv_wh` | Wu-Hausman; `diagnostic_endogeneity_test` | `wu_hausman()`, `durbin()`, `wooldridge_score` | |

\* fixest's `fitstat(, "kpr")` is a chi-squared rank statistic with a p-value, so it is mapped
here, although fixest's help calls it "the Kleibergen-Paap test for weak instruments". It isn't
the rk Wald F (`e(rkf)`). To be checked against ivreg2 on the same data.

`structures.first_stage` (`kind: "object"`) keeps the first-stage summaries that aren't tests:
a `per_endogenous` list, each entry naming its `endogenous` variable, with `r2`, `partial_r2`
and `shea_partial_r2` (`estat firststage`; ivreg2 `e(first)` `pr2`, `sheapr2`; linearmodels
`rsquared`, `partial.rsquared`, `shea.rsquared`).

ivreg2's `e(widstat)` is Cragg-Donald under iid errors and Kleibergen-Paap otherwise; writers
map it to whichever of the two it is.

## Other names

- `meta.estimator.method`: `2sls`, `liml`, `gmm`, `cue`, `kclass`, `fuller`.
- `metrics.kappa` (`ivregress` `e(kappa)`, ivreg2 `e(lambda)`, linearmodels `kappa`) and
  `metrics.fuller` (ivreg2 `e(fuller)`).
- The fitted endogenous term is `fit_x` in fixest and `x` elsewhere; `canonical` matches
  them.

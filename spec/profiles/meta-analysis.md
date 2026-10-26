# Profile `meta-analysis/0.1`

Status: draft. Schema: [`schema/profiles/meta-analysis-0.1.json`](../../schema/profiles/meta-analysis-0.1.json).
Kind: standard. Builds on the core only.

Meta-analyses and meta-regressions of study-level effect sizes. Surveyed 2026-10-25: from
source, R metafor 5.3-1 (wviechtb/metafor @ bc2016e), R meta 9.0-0 (guido-s/meta @ d100dde)
and statsmodels 0.15 `combine_effects`; Stata `meta` from documentation. Network meta-analysis,
individual-participant-data models and Bayesian meta-analysis (bayesmeta, brms) were not
surveyed.

## Requirements

- `meta.estimator.method`: `random_effects`, `common_effect`, `meta_regression`, `multilevel`,
  `bayesian`.
- `specification.meta_analysis.effect_measure`.
- At least one pooled row with a `meta_analysis` object (`model`: `common`, `random`,
  `moderator`), `estimate` and `std_error`.
- `metrics.k`, `q` and `q_df`.
- Random-effects models (`random_effects`, `meta_regression`, `multilevel`) also need
  `tau2_method`, `ci_method` and `metrics.tau2`.

Rows are on the analysis scale (log risk ratio, log odds ratio, Fisher's z, ...); the core's
`scale: "exponentiated"` and `measure` mark back-transformed rows.

## Defaults that change results

| | metafor `rma` | meta | statsmodels `combine_effects` | Stata `meta` |
|---|---|---|---|---|
| `tau2_method` | REML | REML | **Paule-Mandel** (`"iterated"`; `"chi2"` = DL) | REML |
| `ci_method` | `z` (`test = "knha"` for Hartung-Knapp) | `z` (`method.random.ci = "classic"`; `settings.meta()` presets switch to HK) | `z` (`use_t`; the "wls" rows rescale) | `z` (`se(khartung)`) |
| Models reported | the one fit | common **and** random | both | the one chosen |
| `prediction_interval` | `predict()` | `prediction = FALSE` | | `predinterval` |
| I² stored as | percent | proportion | proportion | percent |

DerSimonian-Laird remains common in published work, REML is the default in the R packages and
Stata, and statsmodels defaults to Paule-Mandel, so `tau2_method` is required; Hartung-Knapp
intervals are often much wider than z intervals, so `ci_method` is too. **I² is recorded as a
proportion** in `metrics.i2`.

## `specification.meta_analysis`

| Name | metafor | meta | Stata |
|---|---|---|---|
| `effect_measure` | `escalc(measure =)`: `RR`, `OR`, `RD`, `SMD`, `MD`, `ZCOR`, ... | `sm` | `meta esize` (`lnrratio`, `lnoratio`, `hedgesg`, `cohend`, ...); `meta set` for generic |
| `pooling` | `rma.uni` (inverse variance), `rma.mh`, `rma.peto` | `method` (`"MH"` for `metabin`, `"Inverse"`, `"Peto"`) | `common(mhaenszel)`, `common(invvariance)` |
| `continuity_correction` | `escalc(add, to)` | `incr` | `zerocells()` |
| `moderators` | `mods` | `metareg()` | `meta regress` |

Vocabulary for `effect_measure`: `log_rr`, `log_or`, `rd`, `log_hr`, `smd_hedges_g`,
`smd_cohens_d`, `md`, `zcor`, `cor`, `log_irr`, `proportion`, `logit_proportion`, `generic`.

## Metrics and structures

| Name | metafor | meta | statsmodels | Stata |
|---|---|---|---|---|
| `k` | `k` | `k` | `k` | `r(N)` |
| `q`, `q_df`, `q_p` | `QE`, k − p, `QEp` | `Q`, `df.Q`, `pval.Q` | `q` | `r(Q)`, `r(df_Q)`, `r(p_Q)` |
| `tau2`, `tau2_se`, `tau2_ci` | `tau2`, `se.tau2`, `confint()` | `tau2`, `se.tau2`, `lower.tau2`/`upper.tau2` | `tau2` | `r(tau2)` |
| `i2`, `h2` | `I2` / 100, `H2` | `I2`, `H^2` | `i2`, `h2` | `r(I2)` / 100, `r(H2)` |
| `r2_moderators`, `qm` | `R2` / 100; `QM`, `QMdf`, `QMp` | | | `meta regress` |
| row `pi_low`, `pi_high` | `predict()` `pi.lb`, `pi.ub` | `lower.predict`, `upper.predict` | | `predinterval` |

`structures.studies` is a `table` of the study inputs and weights (`study`, `yi`, `vi`,
`weight_common`, `weight_random`), or a link to an attachment when large.
`structures.small_study` holds Egger's and Begg's tests and trim-and-fill (`k0`, side, adjusted
estimate): metafor `regtest()`, `ranktest()`, `trimfill()`; meta `metabias()`, `trimfill()`;
Stata `meta bias`, `meta trimfill`.

## Example

[`schema/examples/meta-analysis.estimation.json`](../../schema/examples/meta-analysis.estimation.json):
a real statsmodels DerSimonian-Laird meta-analysis of the 13 BCG vaccine trials (log risk
ratios). It matches metafor's `rma(method = "DL")`: −0.7141 (SE 0.1787), τ² 0.3088, Q 152.23 on
12 df, I² 92.1%.

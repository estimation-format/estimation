# Profile `did/0.1`

Status: draft. Schema: [`schema/profiles/did-0.1.json`](../../schema/profiles/did-0.1.json).
Kind: standard. Builds on the core only (see "Why not `inference/0.1`" below).

Heterogeneity-robust difference-in-differences and event-study estimators with staggered
treatment timing. Surveyed (2026-10-25) from source: Stata `csdid` 1.71
(friosavila/csdid_drdid @ e368c10) and `did2s.ado` 0.7 (kylebutts/did2s_stata @ be5406f);
R `did` 2.5.1.902 (bcallaway11/did @ 74b88eb) and `did2s` 1.3.0 (kylebutts/did2s @ 3adaf98);
pyfixest 0.60.0 `did2s` / `event_study`. The vocabulary leaves room for imputation
(`did_imputation`, `didimputation`), Sun-Abraham (`eventstudyinteract`, fixest `sunab`) and
extended TWFE (`jwdid`), which were not surveyed.

Tool profiles: [`did2s/0.1`](did2s.md), [`csdid/0.1`](csdid.md).

## Requirements

- `meta.estimator.method`: `callaway_santanna`, `did2s`, `imputation`, `sun_abraham`,
  `extended_twfe`, `stacked` (recommended values; `family: "did"`).
- `specification.did`: `time`, `comparison`, and `cohort` or `treatment` (below).
- `metrics.nobs`: rows used, as in the core.
- `parameters`: `estimate` and `std_error` on every row that isn't dropped, and a `did` object
  on at least one row.
- `structures.vcov`: a default vcov with `type`.

`structures.did` is **expected**: writers SHOULD fill it whenever the tool stores cohort
sizes, cells, a pre-trend test or a uniform band.

### Why not `inference/0.1`

`inference/0.1` requires `p_value` on every row and `metrics.df_residual`. csdid, R `did` and
Stata `did2s` use normal inference and post no residual df, and csdid's wild bootstrap reports
no p-values. So `did/0.1` requires only `estimate` and `std_error`; `p_value` is recorded when
the tool reports it (`null` when it applies but wasn't computed). Records that do meet
`inference/0.1` (R and pyfixest `did2s`, which return fixest/pyfixest fits) claim it as well.

## `specification.did`: the design

| Name | Meaning | csdid | R `did` | `did2s` (Stata / R) | pyfixest |
|---|---|---|---|---|---|
| `time` | calendar period | `time()` | `tname` | a first-stage FE | `tname` |
| `unit` | unit id; `null` for repeated cross sections | `ivar()`, `e(id)` | `idname` | `unit()` / first-stage FE | `idname` |
| `cohort` | first treated period | `gvar()`, `e(ggroup)` | `gname` | — | `gname` |
| `never_treated_code` | cohort value of never-treated units | `0` | `0` | — | `0` |
| `treatment` | 0/1 treated-observation indicator | — | — | `treatment` | `is_treated` (built) |
| `panel` | panel (true) or repeated cross sections | `ivar()` given | `panel` | — | true |
| `balanced` | panel balanced before estimation | | `!allow_unbalanced_panel` | | |
| `comparison` | `never_treated`, `not_yet_treated`, `untreated` | `e(control_group)` (`notyet`) | `control_group` | `untreated` (fixed) | `untreated` |
| `anticipation` | periods of anticipation | 0 (no option) | `anticipation` | — | — |
| `base_period` | `varying` or `universal` | `e(typebase)` | `base_period` | — | — |
| `covariates` | covariates | varlist after the outcome | `xformla` | in `first_stage` | `xfml` |

`untreated` means every untreated observation (never-treated and not-yet-treated rows),
which is what imputation estimators fit the counterfactual on.

csdid's `typebase` is `default` (a varying base period), `long` or `long2` (long differences
from g−1). The `csdid` profile records the option itself in `specification.options.typebase`;
writers map it to `base_period` only when they know it matches R's definition.

`specification.options.outcome_model` is the Callaway-Sant'Anna 2×2 estimator: csdid
`method()` (`reg`, `ipw`, `stdipw`, `dripw`, `drimp`), R `did` `est_method` (`"reg"`, `"ipw"`
= standardized IPW, `"dr"` = `dripw`).

## Parameter rows: `parameters[*].did`

Each treatment-effect row carries `did: {type, ...}`. Rows without it (a covariate in a did2s
second stage) are not treatment effects.

| `type` | Required | Meaning | csdid | R `did` | did2s / pyfixest |
|---|---|---|---|---|---|
| `att_gt` | `cohort`, `period` | ATT(g, t); `base_period` is recommended | `g2004:t_2003_2004` | `att_gt`: `group`, `t` (tidy `ATT(2004,2004)`) | — |
| `event` | `event_time` | effect e periods after treatment; `binned` for pooled endpoints | `Tm3`, `Tp0` (`agg(event)`) | `aggte(type = "dynamic")`: `egt` | relative-time dummies (`rel_year::-2`) |
| `pre_avg`, `post_avg` | | averages of the pre / post event-time effects | `Pre_avg`, `Post_avg` | dynamic `overall.att` is the post average | — |
| `group` | `cohort` | average effect for a cohort | `agg(group)` | `aggte(type = "group")` | — |
| `calendar` | `period` | average effect in a calendar period | `agg(calendar)` | `aggte(type = "calendar")` | — |
| `simple` | | overall ATT | `ATT` (`agg(simple)`) | `aggte(type = "simple")` | single treatment dummy |

`weight` holds the row's aggregation weight when the tool reports it.

### Pointwise and uniform intervals

`conf_low`/`conf_high` are always **pointwise**, as in the core. A simultaneous (uniform)
band goes in `did.band_low`/`did.band_high`, with its critical value and level in
`structures.did.uniform_band`.

This matters for R `did`: when `bstrap = TRUE` and `cband = TRUE` (the defaults), tidy's
`conf.low`/`conf.high` are the **uniform** band (`att ± c · se`), and the pointwise interval is
`point.conf.low`/`point.conf.high`. Writers put `point.conf.*` in `conf_low`/`conf_high` and
`conf.*` in `band_low`/`band_high`. csdid with `wboot` stores one interval in `e(cband)`:
uniform when `e(citype)` is `uniform` (the default), pointwise otherwise.

## `metrics`

| Name | Meaning | csdid | R `did` | did2s | pyfixest |
|---|---|---|---|---|---|
| `nobs` | rows used | `e(N)` | rows of the data used | `e(N)`; `nobs()` | `_N` |
| `n_units` | units (panel) | | `n` / `DIDparams$id_count` | | |
| `n_periods` | periods | `words(e(tlev))` | `time_periods_count` (`nT`) | | |
| `n_cohorts` | treated cohorts | `words(e(glev))` | `treated_groups_count` (`nG`) | | |
| `n_never_treated` | never-treated units | | | | |
| `n_not_identified` | rows dropped: no untreated rows in their FE level | | | Stata `e(N_noid)` | |

**R `did` reports units, not rows**: `glance()`'s `nobs` and the `MP` object's `n` count units
in a panel. Writers put that in `n_units` and the row count in `nobs`.

## `structures.vcov`

| `type` | Meaning | Tools |
|---|---|---|
| `influence_function` | V = IF′IF / n², from the estimators' influence functions (summed by cluster when clustered) | csdid (default); R `did` with `bstrap = FALSE` |
| `multiplier_bootstrap` | multiplier bootstrap of the influence function | R `did` (default; `biters`) |
| `wild_bootstrap` | wild bootstrap of the RIFs | csdid `wboot` (`e(reps)`, `e(wbtype)`) |
| `two_stage_gmm` | cluster-robust GMM sandwich that accounts for the first stage | did2s (Stata, R), pyfixest |
| `cluster_bootstrap` | block bootstrap over clusters | R did2s `bootstrap = TRUE` (`n_bootstraps`) |

`reps`, `bootstrap_weights` and `seed` describe a bootstrap. None of these tools applies a
small-sample factor; writers SHOULD still record `ssc: {convention: "<tool>", formula: "none"}`
so a reader can tell "none" from "unknown". In a panel the influence function is per unit, so
csdid's and R `did`'s default vcov is clustered by unit: record `cluster: ["<unit>"]`.

## `structures.did`

A `kind: "object"` structure, all fields optional:

- `cohorts`: `[{cohort, never_treated, n_units, n_rows}]`, never-treated included.
- `periods`: the calendar periods in the sample.
- `cells`: one entry per ATT(g,t) 2×2 comparison, `{cohort, period, base_period, n, n_control,
  n_treated, error}` (csdid `e(gtt)`: `cohort t0 t1 error N N_cntr N_trt`).
- `pretrend`: the joint pre-trend test, `{name, statistic, df, p_value, distribution}` (csdid
  `estat pretrend`; R `did` `W`, `Wpval`).
- `uniform_band`: `{critical_value, level, method, applies_to}` (R `did` `c`, `crit.val.egt`).

## Examples

- [`schema/examples/did2s.estimation.json`](../../schema/examples/did2s.estimation.json): a
  real pyfixest `did2s` event study (claims `inference/0.1`, `did/0.1`, `did2s/0.1`).
- [`schema/examples/csdid.estimation.json`](../../schema/examples/csdid.estimation.json):
  csdid on `mpdta` with `agg(event)` (a shape example; see its `meta.notes`).

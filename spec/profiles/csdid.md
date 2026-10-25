# Profile `csdid/0.1`

Status: draft. Schema: [`schema/profiles/csdid-0.1.json`](../../schema/profiles/csdid-0.1.json).
Kind: tool. `x-extends`: [`did/0.1`](did.md), with no deviations.

Records of Stata `csdid` (Rios-Avila, Sant'Anna and Callaway), the Callaway-Sant'Anna (2021)
estimator, surveyed from `csdid.ado` 1.71 and `csdid_estat.ado` (friosavila/csdid_drdid @
e368c10). `csdid2` was not surveyed. R `did` estimates the same model; its records claim
`did/0.1` (the field mappings are on that page).

## Requirements

Everything `did/0.1` requires (the profile includes its rules), plus:

- `meta.estimator.method: "callaway_santanna"`.
- `specification.did.cohort` (`gvar()`), and `comparison` `never_treated` or
  `not_yet_treated` (`e(control_group)`). csdid switches to not-yet-treated by itself when
  the sample has no never-treated units; record what it used.
- `specification.options`: `method` (`e(method)`: `drimp`, `dripw`, `reg`, `ipw`, `stdipw`;
  resolved, so `dripw` with covariates and `reg` without when `method()` is omitted), `agg`
  (`e(agg)`, `attgt` when omitted) and `typebase` (`e(typebase)`: `default`, `long`,
  `long2`).
- A default vcov of type `influence_function` or `wild_bootstrap` (`e(vcetype) == "WBoot"`).
- `structures.did.cells`, from `e(gtt)`, which csdid always stores.

## Stored results

| csdid | Record |
|---|---|
| `e(b)`, `e(V)` | `parameters` and the default vcov: the ATT(g,t) with `agg(attgt)`, otherwise the aggregation |
| `e(b_attgt)`, `e(V_attgt)` | ATT(g,t) rows (`did.type: "att_gt"`) and a second vcov with `default: false` (skip when `agg(attgt)`: they equal `e(b)`, `e(V)`) |
| `e(gtt)` (`cohort t0 t1 error N N_cntr N_trt`) | `structures.did.cells` (`cohort`, `base_period`, `period`, `error`, `n`, `n_control`, `n_treated`) |
| `e(N)` | `metrics.nobs` |
| `e(glev)`, `e(tlev)` | `n_cohorts`, `structures.did.periods` |
| `e(id)`, `e(ggroup)` | `specification.did.unit`, `cohort` |
| `e(clustvar)`, `e(N_clust)` | vcov `cluster`, `n_clusters`; without `cluster()`, the cluster is `e(id)` (the influence function is per unit) |
| `e(reps)`, `e(wbtype)`, `e(seed)`, `e(citype)` | vcov `reps`, `bootstrap_weights`, `seed`; `options.citype` |
| `e(cband)` (`b se t ll ul`) | with `e(citype) == "uniform"`: `did.band_low`/`band_high`; with `pointwise`: `conf_low`/`conf_high` |
| `e(riffile)` | `options.saverif` (a path: identifying) |
| `estat pretrend`: `r(chi2)`, `r(pchi2)`, `r(df)` | `structures.did.pretrend` |
| `estat simple/group/calendar/event`: `r(b)`, `r(V)` | more rows with the matching `did.type`, and their own non-default vcov |

The variance is V = IF′IF / n² (cluster sums of the influence function when clustered), with
no G/(G−1): record `ssc: {convention: "csdid", formula: "none"}`. With the wild bootstrap
csdid shows no p-values; rows record `p_value: null`.

## Term names and `did` rows

| `e(b)` column | `did` |
|---|---|
| `g2004:t_2003_2004` (equation `g<cohort>`, `t_<base>_<period>`) | `{type: "att_gt", cohort: 2004, base_period: 2003, period: 2004}` |
| `Pre_avg`, `Post_avg` (`agg(event)`) | `{type: "pre_avg"}`, `{type: "post_avg"}` |
| `Tm3`, `Tp0`, `Tp2` (`agg(event)`) | `{type: "event", event_time: -3}`, `0`, `2` |
| `ATT` (`agg(simple)`) | `{type: "simple"}` |

The base period in an ATT(g,t) name is the one actually compared with: g−1 after treatment,
t−1 before it with the default `typebase`.

## Example

[`schema/examples/csdid.estimation.json`](../../schema/examples/csdid.estimation.json):
`csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) agg(event)` on
`mpdta`. A shape example: the values were computed with the csdid Python port (same
estimator and variance formula), not by Stata, and match the published R `did` results.

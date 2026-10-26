# Profile `med2s/0.1`

Status: draft. Schema: [`schema/profiles/med2s-0.1.json`](../../schema/profiles/med2s-0.1.json).
Kind: tool. `x-extends`: [`mediation/0.1`](mediation.md), with no deviations.

Records of med2s (Matherly; Stata package 4.1.1, 2026-09-22): natural direct and indirect
effects in staggered-adoption difference-in-differences, built on the two-stage DiD first
stage (Gardner 2021; the first-stage Mata is adapted from `did2s`). Mapped from the package
source and its help files: `med2s`, `med2s_ci`, `med2s_diag`, `med2s_sens`, `med2s_report`.

## What a record covers

The inference med2s recommends comes from `med2s_ci`: the adjusted quantities have no analytic
SE, so a record describes a `med2s_ci` run (point estimates, cluster bootstrap, percentile
intervals), optionally with the `med2s_diag` diagnostics and the `med2s_sens` breakdown analysis
for the same mediator and options. One record per mediator; `med2s_report` builds the
cross-mediator table from several records' draws. A bare `med2s` run has no inference for the
indirect effect and does not meet `mediation/0.1`.

## Requirements

Everything `mediation/0.1` requires (the profile includes its rules), plus:

- `meta.estimator.method: "med2s"`.
- `specification.did`, as in [`did/0.1`](did.md): `unit`, `time`, `treatment`,
  `comparison: "untreated"`, `anticipation` (`anticipation()`, default 0).
- `specification.clusters`: `cluster()`, which must be the level at which treatment is
  assigned.
- `specification.mediation`: one mediator; `inference` `bootstrap` with `ci_type: "percentile"`,
  `reps` (1000) and `seed`.
- `specification.options`: `adjust` (`placebo`, the default, or `none`), `adjgap` (1), `adjk`
  (3), `version` (`dev`, `levels`, `both`) and `sigcrit` (1.645; `null` when off); also
  `absorb`, `covars`, `covarsm`, `x`, `minsignal`.
- A `med2s` object on each med2s quantity row.
- `extensions.med2s` with `schema: "med2s/0.1"` and `signal`.

## Parameter rows

One row per quantity `med2s_ci` collects, `term` the `r()` name, with `estimate`, `std_error`
(bootstrap, `r(s_bse)`), `conf_low`/`conf_high` (percentile, `r(s_lo)`, `r(s_hi)`) and
`med2s: {quantity, adjustment, n_valid}` (`r(s_nv)`):

| `term` | `mediation.effect` | `med2s.adjustment` |
|---|---|---|
| `total` | `total` (also `naive_se`, `r(total_se)`) | `none` |
| `a` | `a` | `none` |
| `b_dev` | `b` | `placebo` |
| `dev_nie` | `indirect` (headline) | `placebo` |
| `dev_nde` | `direct` (headline) | `placebo` |
| `b_dev_unadj`, `dev_nie_unadj`, `dev_nde_unadj` | — | `unadjusted` |
| `b_lev`, `lev_nie`, `lev_nde` (`version(levels\|both)`) | — | `levels` (a comparison, never placebo-adjusted) |
| `sshare` | — | `placebo` |

Only the headline rows carry `mediation.effect`, so a reader taking "the indirect effect" gets
the adjusted one.

## `extensions.med2s`

| Block | Content | Source |
|---|---|---|
| `signal` | `d`, `se`, `t_d`, `t_d_squared`, `n_clusters`, `flag` (low signal: report "not identified"), `share` (1 − v0/v1); `boot_d` (`std_error`, interval, one-sided lower bound, `n_valid`), `boot_flag`, `se_ratio` | `r(sig_*)`, `r(lowsignal)`, `r(sshare)`; `med2s_ci` `r(d_*)`, `r(boot_lowsignal)`, `r(se_ratio)` |
| `moments` | `c1`, `v1`, `c0`, `v0` | `r(mom_*)` |
| `placebo` | `n_rows`, `mean_uY`, `mean_uM`, `slope` (b_pl and SE), `composition` (adoption index and pre-periods, placebo vs treated) | `r(pl_*)`, `r(b_pl*)`, `r(*_adopt_idx)`, `r(*_npre)` |
| `a_levels` | `a_raw` = a + `composition` | `r(a_raw)`, `r(composition)` |
| `counts` | treated rows, rows removed by `anticipation()` | `r(ntreat)`, `r(antic_n)` |
| `diagnostics` | `anticipation` (pre-adoption ATTs of Y and M, flag), `placebo_grid` (a matrix structure, columns `gap k N b_pl b_pl_se signal t_d b_adj nie adopt_idx npre`), `trend_d1` (shares, statistics, p-values, `reference` F or cluster t, beta, flag), `trend_d4` (event-time slopes and growth), `clusters` (G, treated G, units, effective G, HHI, nested) | `med2s_diag` `r(ant_*)`, `r(placebo)`, `r(d1_*)`, `r(d4_*)`, `r(cl_*)` |
| `sensitivity` | `pi`, `breakdown_share`, `grid` (a matrix structure), `draws` (attachment id of the saved draws) | `med2s_sens` `r(breakdown_share)`, `r(breakdown)`, `r(sens)` |

The flag labels an estimate; it never drops one. A flagged mediator stays in the record with
its rows, and readers report it as not identified, as the reporting guide asks.

## Example

[`schema/examples/med2s.estimation.json`](../../schema/examples/med2s.estimation.json): a shape
example with illustrative numbers (the "Store visits" row of the med2s reporting guide), not
output from a real run.

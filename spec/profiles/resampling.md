# Profile `resampling/0.1`

Status: draft. Schema: [`schema/profiles/resampling-0.1.json`](../../schema/profiles/resampling-0.1.json).
Kind: standard. Builds on the core only.

Inference by resampling: wild (cluster) bootstrap, pairs and cluster bootstrap, jackknife,
permutation and randomization inference. Surveyed 2026-10-25: from source, Stata `boottest`
(droodman/boottest @ ab5e99a), R fwildclusterboot 0.14.3 and Python wildboottest 0.3.2 (as
called by pyfixest); Stata's `bootstrap` and `jackknife` prefixes, `ritest` and R `ri2` from
documentation.

The record also claims the model's own profile. The core columns (`std_error`, `p_value`,
`conf_low`, `conf_high`) keep the analytic results; resampled ones go in each row's
`resampling` object, so both can be compared.

## Requirements

- `specification.resampling` with `method` and `reps`.
- At least one row with `resampling`, holding a `p_value` or `conf_low`/`conf_high`.

## Settings and defaults

| Name | boottest | fwildclusterboot | wildboottest / pyfixest | Stata `bootstrap` |
|---|---|---|---|---|
| `reps` | `reps()` (999) | `B` (required) | `reps` (required) | `reps()` (50) |
| `seed` | `seed()` | `seed` | `seed` | `seed()` |
| `cluster` | `bootcluster()` (the model's clusters) | `bootcluster` (`"max"`) | `cluster` | `cluster()` |
| `weights` | `weighttype()` (rademacher) | `type` (`"rademacher"`) | `weights_type` (`"rademacher"`) | — |
| `impose_null` | yes unless `nonull` | `impose_param_null` (TRUE) | `impose_null` (True) | — |
| `variant` | | `bootstrap_type` (`"fnw11"`) | `bootstrap_type` (`"11"`) | — |
| `p_value_type` | `ptype()` (symmetric) | `p_val_type` (two-tailed) | two-sided | — |
| `ci_method` | test inversion | test inversion | | normal (`estat bootstrap`: percentile, bc, bca) |
| `small_sample` | `small` / `nosmall` | `ssc` | `k_adj`, `G_adj` | |

Per row: `statistic`, `p_value`, `conf_low`, `conf_high`, `std_error` (when the method gives
one) and `null_value`. A resampled p-value of 0 means no replication was as extreme; its
resolution is about 1/reps. `metrics.n_reps_failed` records Stata's `e(N_misreps)`.

## Example

[`schema/examples/resampling.estimation.json`](../../schema/examples/resampling.estimation.json):
a real pyfixest regression with CRV1 standard errors (claims `inference/0.1` too) and a
restricted wild cluster bootstrap of one coefficient, 9999 Rademacher replications.

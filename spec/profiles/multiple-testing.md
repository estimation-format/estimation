# Profile `multiple-testing/0.1`

Status: draft. Schema: [`schema/profiles/multiple-testing-0.1.json`](../../schema/profiles/multiple-testing-0.1.json).
Kind: standard. Builds on the core only.

p-values adjusted for a family of hypotheses. Surveyed 2026-10-25: from source, statsmodels
`multipletests` and pyfixest 0.60.0 `bonferroni`, `rwolf`, `wyoung`; R `p.adjust` (wch/r-source, `stats/R/p.adjust.R`; `"fdr"` is an alias of `"BH"`); Stata `rwolf`, `wyoung` and `qqvalue` from documentation.

## Requirements

- `specification.multiple_testing`: `method`, `controls` (`fwer` or `fdr`) and `n_tests`; for
  resampling-based methods also `reps`, `seed` and `resampling`.
- `parameters[*].p_value_adjusted` on the tested rows (at least one).

A family can span several models, typically one coefficient across several outcomes: the tested
rows of each model sit in one record, told apart by `response`; `records` can list the ids of
the full model records. `test_family` separates families when a record holds more than one.

## Methods and defaults

| `method` | Controls | R `p.adjust` | statsmodels `multipletests` | pyfixest | Stata |
|---|---|---|---|---|---|
| `bonferroni`, `sidak` | FWER | `"bonferroni"` | `bonferroni`, `sidak` | `bonferroni()` | |
| `holm`, `holm_sidak` | FWER | `"holm"` (**default**) | `holm`, `hs` (**default**) | | |
| `hochberg`, `hommel` | FWER | `"hochberg"`, `"hommel"` | `simes-hochberg`, `hommel` | | |
| `bh`, `by` | FDR | `"BH"`, `"BY"` | `fdr_bh`, `fdr_by` | | `qqvalue` |
| `romano_wolf` | FWER | | | `rwolf()` (wild bootstrap) | `rwolf` |
| `westfall_young` | FWER | | | `wyoung()` | `wyoung` |

The two common defaults differ (`p.adjust` Holm, `multipletests` Holm-Šidák), so the method is
always recorded. Resampling-based adjusted p-values are bounded below by the replications:
pyfixest's Romano-Wolf floor is 1/reps, its Westfall-Young floor is 0.

## Example

[`schema/examples/multiple-testing.estimation.json`](../../schema/examples/multiple-testing.estimation.json):
a real pyfixest Romano-Wolf adjustment of one coefficient across two outcome models (9999
wild-bootstrap replications), with the Westfall-Young and Bonferroni values in its notes.

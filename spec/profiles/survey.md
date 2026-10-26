# Profile `survey/0.1`

Status: draft. Schema: [`schema/profiles/survey-0.1.json`](../../schema/profiles/survey-0.1.json).
Kind: standard. Builds on the core only.

Estimates from complex survey designs. Surveyed 2026-10-25: from source, R survey 4.5
(cran/survey @ 4834b8b) and Python samplics 0.6.1 (archived by its authors in favor of `svy`);
Stata `svyset` / `svy:` from their help files. Combines with the analysis model's profile.

## Requirements

- `specification.survey_design` with `weights`, `strata`, `psu`, `fpc`, `variance` and
  `single_psu` (each may be `null` or `[]` when the design has none, but it must be stated).
- `estimate` and `std_error` on every row that isn't dropped.
- `metrics.nobs`.
- A default vcov with `type` (`linearized`, `brr`, `fay`, `jackknife`, `bootstrap`, `sdr`).

## Settings that change standard errors

| Name | R survey | Stata | samplics |
|---|---|---|---|
| `weights` | `weights` / `probs` | `[pw=]` | `samp_weight` |
| `strata` | `strata` | `strata()` | `stratum` |
| `psu` (per stage) | `ids` | `svyset psu \|\| ssu` | `psu`, `ssu` |
| `nest` | `nest` (FALSE) | | |
| `fpc.convention` | population sizes (or sampling fractions if < 1) | population sizes or sampling fractions | **1 − n/N** |
| `variance` | linearization; `svrepdesign(type = BRR, Fay, JK1, JKn, bootstrap, ...)` | `vce()` (linearized default) | `TaylorEstimator`; `ReplicateEstimator` |
| `replicates.scale`, `mse` | `scale`, `rscales`, `mse` | `mse` | |
| `single_psu` (default) | **fail** (`options(survey.lonely.psu)`) | **missing** SEs (`singleunit()`) | **error** (`single_psu`) |
| `subpopulation` | `subset(design, ...)` | `subpop()` | `domain` |
| `calibration` | `postStratify`, `rake`, `calibrate` | `poststrata()`, `rake()` | |

The same fpc column means different things to different tools, so `fpc` records its
`convention`. Domain estimates must use the full design (`subpopulation`), not a subset of
rows; a record that subset the data is a different analysis.

## Design counts and effects

| Name | R survey | Stata | samplics |
|---|---|---|---|
| `metrics.n_strata`, `n_psu` | | `e(N_strata)`, `e(N_psu)` | `nb_strata`, `nb_psus` |
| `metrics.population_size` | | `e(N_pop)` | |
| `metrics.df_design` | `degf()` | `e(df_r)` | `degree_of_freedom` |
| `parameters[*].deff`, `deft` | `deff = TRUE` | `estat effects` | `deff=True` |

R's `svyglm` tests with the design df; samplics uses normal tests.

## Example

[`schema/examples/survey.estimation.json`](../../schema/examples/survey.estimation.json): a
real samplics `SurveyGLM` on R survey's `apistrat` (stratified by school type, with fpc),
`api00 ~ ell + meals + mobility`. The design checks out against R: samplics' mean of `api00`
is 662.29 (SE 9.409), as R's `svymean` reports.

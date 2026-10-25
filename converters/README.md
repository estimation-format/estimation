# Converters

Worked examples that turn a fitted model into an `estimation` record claiming
`linear-fe/0.1`, using only what each tool stores. They show the profile's mappings on real
output, and they are a starting point for a tool's authors to write records natively. MIT, like
the rest of the code here: copy and adapt freely.

| Tool | File | Tested with |
|---|---|---|
| pyfixest (Python) | [`pyfixest/estimation_pyfixest.py`](pyfixest/estimation_pyfixest.py) | pyfixest 0.60.0 |
| fixest (R) | [`fixest/estimation_fixest.R`](fixest/estimation_fixest.R) | fixest 0.14.2, jsonlite 2.0.0, R 4.6.0 |
| reghdfe (Stata) | [`reghdfe/estimation_write.ado`](reghdfe/estimation_write.ado) | reghdfe 6.13.1, ftools 2.50.0, Stata 18 MP |

`tests/test_converters.py` fits the same four specifications in each tool that is installed
(two-way FE with clustering; a factor, an interaction and weights; iid; HC1) on a panel with
singletons and missing values, validates every record, and checks that the tools agree on N,
singletons, R², the t-test df, coefficients and standard errors.

## Use

```python
import pyfixest as pf
from estimation_pyfixest import to_record
import estimation_format as ef

fit = pf.feols("y ~ x1 + x2 | firm + year", data, vcov={"CRV1": "firm"})
ef.write(to_record(fit, data), "fit.estimation.json")   # write adds the core digest
```

```r
library(fixest)
source("estimation_fixest.R")
fit <- feols(y ~ x1 + x2 | firm + year, data, cluster = ~firm)
estimation_write(estimation_record(fit), "fit.estimation.json")
```

```stata
adopath ++ "path/to/converters/reghdfe"
reghdfe y x1 x2, absorb(firm year) vce(cluster firm)
estimation_write using "fit.estimation.json", replace
```

The R and Stata writers leave out the core digest (optional in the format), because it needs
RFC 8785 canonical JSON. `estimation digest --write fit.estimation.json` adds it.

Each converter handles one OLS fit with absorbed fixed effects (or none). Not handled: IV,
GLMs, multiple-estimation objects (convert each model), fixest `subset`/`split`.

## What each tool stores, and what the converter has to work out

| Record field | pyfixest | fixest | reghdfe |
|---|---|---|---|
| `metrics.nobs` | `_N` | `nobs` | `e(N)` |
| `metrics.n_singletons` | not stored (a warning); from the input data | not stored (a message); from the input data, recovered from `call_env` | `e(num_singletons)` |
| `sample.dropped.missing` | not stored separately: `_na_index` holds the missing and singleton rows together | not stored separately: `obs_selection$obsRemoved` likewise | not stored; the converter marks out the model's variables |
| `metrics.df_residual` | `_dfd`: the Wald test's denominator df, min(G) − 1 when clustered, else N − k − all FE levels (one below fixest per extra FE); recorded with its definition | `df.residual()`: N − K | `e(df_r)`: min(G) − 1 when clustered, recorded with its definition |
| `vcov.df_t` | `_df_t` | `attr(vcov, "df.t")` | `e(df_r)` |
| `metrics.sigma` | `_rmse` = sqrt(RSS / N); recorded with its definition | `sigma()` = sqrt(RSS / (N − K)) | `e(rmse)` = sqrt(RSS / df_r) |
| `vcov.ssc` | `_ssc_dict` and the factor `_ssc` | `attr(vcov, "ssc")`, `df.K`; no numeric factor | `e(dofmethod)`, `e(df_a)`, `e(df_a_nested)`; no numeric factor |
| `fixed_effects[*].levels` | `_fe` (counted) | `fixef_sizes` | `e(dof_table)` |
| iterations, convergence | not stored | `iterations` (per variable) | `e(ic)`, `e(converged)` |

A point for the pyfixest and fixest authors: storing the singleton count and the
missing-value count separately would let a writer fill `n_singletons` without the input data.

Defaults: with fixed effects and no `vcov`, both fixest 0.14 and pyfixest 0.60 use iid
standard errors (older fixest clustered by the first fixed effect); reghdfe's default is
unadjusted too. The record states the vcov actually used, so this only matters when
comparing calls, not records.

# estrec for Stata

`estrec write` saves the results of a Stata estimation command as an `estimation` record.
Run it right after the command:

```stata
net install estrec, from("https://raw.githubusercontent.com/estimation-format/estimation/main/stata") replace
sysuse auto, clear
regress price mpg weight, vce(cluster rep78)
estrec write using "price.estimation.json", replace
```

Or, from a clone: `net install estrec, from("path/to/estimation/stata") replace`.

| Command | Profiles claimed (level 4) | Notes |
|---|---|---|
| `regress` | inference | the model-based vcov is kept beside a robust or cluster one |
| `areg` | inference, linear-fe | K counts the absorbed levels even when nested in the clusters |
| `xtreg, fe` | inference, linear-fe | the panel variable is the fixed effect; `xtset` in `specification.state` |
| `xtreg, re` | inference | z tests; `df_residual` is N − K, labelled |
| `reghdfe` | inference, linear-fe | same record as `converters/reghdfe` |
| `ivregress` | inference, iv | runs `estat firststage`, `overid` and `endogenous` (`noestat` skips them) |
| `ivreg2` | inference, iv | first-stage tests with `first`/`ffirst`, C test with `endog()` |
| `ivreghdfe` | inference, iv, linear-fe | |
| `logit`, `logistic`, `probit`, `poisson`, `nbreg` | glm | deviance computed for the record (−2 log L for 0/1 outcomes; from `predict, n` for counts) |
| `glm` | inference, glm | `glm, irls` stores no convergence flag, so only inference |
| anything else with `e(b)`, `e(V)` | none | core fields only |

Tested with Stata 18 MP, reghdfe 6.13.1, ivreg2 4.1.12 and ivreghdfe 1.1.4
(`tests/test_stata.py`: each command at every disclosure level validates with no warnings
and reproduces Stata's results table).

## Small-sample corrections

Recorded in `structures.vcov[*].ssc`, checked against each other in Stata 18:

| Command | iid | robust | cluster |
|---|---|---|---|
| `regress`, `ivregress, small`, `ivreg2, small` | s² = RSS/(N−K) | HC1, N/(N−K) | (N−1)/(N−K) · G/(G−1) |
| `areg` | K = rank + df_a | same | same, absorbed levels counted even when nested |
| `xtreg, fe` | K = rank + df_a | (cluster on the panel) | K = rank |
| `reghdfe`, `ivreghdfe` | K = df_m + df_a | same | same (nested levels not counted) |
| `ivregress`, `ivreg2` (no `small`) | s² = RSS/N | HC0, none | no factor |
| ML (`logit`, `poisson`, `glm`, ...) | none (OIM) | N/(N−1) | G/(G−1) |

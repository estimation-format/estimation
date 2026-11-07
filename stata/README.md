# estrec for Stata

`estrec write` saves the results of a Stata estimation command as an estrec record (an estimation record).
Run it right after the command:

```stata
net install estrec, from("https://raw.githubusercontent.com/estrec/estrec/main/stata") replace
sysuse auto, clear
regress price mpg weight, vce(cluster rep78)
estrec write using "price.estrec.json", replace
```

Or, from a clone: `net install estrec, from("path/to/estrec/stata") replace`.

| Command | Profiles claimed (level 4) | Notes |
|---|---|---|
| `regress` | inference | the model-based vcov is kept beside a robust or cluster one |
| `areg` | inference, linear-fe | K counts the absorbed levels even when nested in the clusters |
| `xtreg, fe` | inference, linear-fe | the panel variable is the fixed effect; `xtset` in `specification.state` |
| `xtreg, re` | inference | z tests, so no `df_residual` and `df_t` null |
| `reghdfe` | inference, linear-fe | same record as `converters/reghdfe` |
| `ivregress` | inference, iv | without `small`, z tests (no `df_residual`); runs `estat firststage`, `overid` and `endogenous` (`noestat` skips them) |
| `ivreg2` | inference, iv | as `ivregress` without `small`; first-stage tests with `first`/`ffirst`, C test with `endog()` |
| `ivreghdfe` | inference, iv, linear-fe | |
| `logit`, `logistic`, `probit`, `poisson`, `nbreg` | inference, glm | z tests (no `df_residual`). After `poisson`, `estat gof`'s deviance and Pearson goodness-of-fit (the deviance equals `glm`'s); after `logit`, `logistic`, `probit`, its Pearson test over covariate patterns; `nbreg` reports no deviance |
| `glm` | inference, glm | `glm, irls` stores no convergence flag, so only inference |
| anything else with `e(b)`, `e(V)` | none | core fields only |

Tested with Stata 18 MP, reghdfe 6.13.1, ivreg2 4.1.12 and ivreghdfe 1.1.4
(`tests/test_stata.py`: each command at every disclosure level validates with no warnings
and reproduces Stata's results table). estrec records what Stata reports, under the
record's name for it, and does not compute statistics of its own: `nobs` is `e(N)`, which
with frequency weights is the sum of the weights, as Stata counts it.

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

# estrec (R)

Writes fitted models as `estimation` records: one JSON file per model, holding what was
estimated, what came out, and how and where it ran. Version 0.1 writes **fixest `feols`**
fits: OLS and IV, with or without fixed effects, including multiple estimations
(`c(y1, y2)`, `csw()`, `split`, `fsplit`, `subset`). MIT.

```r
# install.packages("remotes")
remotes::install_github("estimation-format/estimation", subdir = "r")
```

```r
library(fixest)
library(estrec)

fit <- feols(y ~ x1 + x2 | firm + year, data, cluster = ~firm)
write_estimation(fit, "fit.estimation.json")

# Several vcovs in one record: the first is the default and gives the standard errors
write_estimation(fit, "fit.estimation.json", vcov = list(~firm, "hetero", ~firm + year))

# A multiple estimation writes one numbered file per model: fits-1.estimation.json, ...
fits <- feols(c(y1, y2) ~ csw(x1, x2) | firm, data, split = ~region)
write_estimation(fits, "fits.estimation.json")

rec <- to_estimation(fit)   # the record as a list

# Hypothesis tests, computed from the record's own coefficients and vcov
rec <- to_estimation(fit, vcov = list(~firm, "hetero"), tests = c("x1 = x2", "x1 + x2"))
rec <- add_test(rec, "x1 = 0, x2 = 0", vcov = "HC1")              # Wald F
rec <- add_test(rec, wald(fit, keep = "^x", print = FALSE))       # a fixest test, as is
write_estimation(rec, "fit.estimation.json")
```

Tests go in the record's `tests` list: fixest's joint Wald test of the coefficients and, for
IV, the first-stage and identification tests (`origin: "estimation"`), plus each test you add
(`origin: "postestimation"`). A restriction with `=` is a Wald test (F with the vcov's t-test
df). An expression without `=` is a linear combination: estimate, SE, interval and t test.
Adding a test doesn't change the results, so it keeps the core digest valid.

## What a record holds

| Section | From fixest |
|---|---|
| `parameters` | estimates, SEs, t, p, CIs (`conf_level`), canonical term names; collinear terms marked `dropped` |
| `metrics` | `nobs`, `n_singletons`, `df_residual`, R², within R², sigma, RSS/TSS, log-likelihoods |
| `specification` | call, formula, terms, fixed effects, clusters, weights, endogenous/instruments; `sample`: rows in, the `subset`/`split` restriction, and rows dropped by reason (missing, non-finite, zero weights, singletons); options (`fixef.rm`, tolerances) |
| `structures` | each vcov with its type, clusters and cluster counts, df for t tests and the small-sample correction (`ssc`); fixed-effect level counts; convergence |
| `tests` | fixest's joint Wald test; IV first-stage F and Wald F, Cragg-Donald, Kleibergen-Paap, Wu-Hausman and Sargan; tests you add |
| `provenance` | fixest, R and loaded package versions; OS, BLAS/LAPACK, threads; user, host and command line (`identifying = FALSE` leaves these out) |

Records claim `inference/0.1`, plus `linear-fe/0.1` with fixed effects and `iv/0.1` for IV.

**Sample drops need the data.** fixest stores only which rows it removed, not why. To split
the drops by reason, estrec looks at the data the model was fitted on: it takes `data =`, or
else finds the data the way fixest's own methods do (in the fit's call environment). When the
data can't be found, for example after the fit was saved with `saveRDS` and reloaded, the drops
are recorded as `other` and the record carries a warning. Pass `data =` to fix that.

## Checking and sharing records

The Python reference tools validate, digest and redact records:

```bash
pip install "estimation-format[jsonschema] @ git+https://github.com/estimation-format/estimation"
estimation validate fit.estimation.json
estimation redact fit.estimation.json -o shareable.estimation.json   # drops user, host, argv
python -c "import estimation_format as ef, sys; p = sys.argv[1]; ef.write(ef.read(p), p)" fit.estimation.json  # adds the core digest
```

estrec doesn't write the core digest (`meta.core_digest`, optional) yet: it needs RFC 8785
canonical JSON.

## Not yet

- `feglm`/`fepois` (`glm/0.1`), `lm`/`glm` and other classes through `insight`, nonlinear
  tests (`nlcom`-style, by the delta method).
- Tests: `tests/test-fixest.R` (base R). It validates every record when the `estimation` CLI
  is on `PATH` or `ESTREC_VALIDATOR` names it.

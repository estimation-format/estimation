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
recs <- to_estimation(list(base = fit, full = fit2))   # a list of fits: a list of records

# Test results: run the test with the function you use, and record its result
rec <- add_test(rec, wald(fit, keep = "^counter::-([2-9]|1[0-9]|20):"), label = "pre-trends")
rec <- add_test(rec, marginaleffects::hypotheses(fit, "b1 + b2 * 0.25 = 0"))
rec <- add_test(rec, car::linearHypothesis(fit, "x1 = x2"))
rec <- to_estimation(fit, tests = list(wald(fit, keep = "^x")))   # or when writing the record
write_estimation(rec, "fit.estimation.json")
```

Tests go in the record's `tests` list: fixest's joint Wald test of the coefficients and, for
IV, the first-stage and identification tests (`origin: "estimation"`), plus each test result you
add (`origin: "postestimation"`). estrec doesn't run tests; it records the statistic, df,
p-value, vcov and hypothesis that the result carries, and the call that made it.
`fixest::wald()` doesn't return which terms it tested, so estrec reads them from the call's
`keep`/`drop`. Adding a test doesn't change the results, so it keeps the core digest valid.

`as_estimation_test()` reads a result into test objects. It has methods for `wald()`,
`marginaleffects::hypotheses()` and other broom-style data frames, `anova` comparisons
(`anova(m1, m2)`, `car::linearHypothesis()`, `lmtest::waldtest()`/`lrtest()`) and `htest`
(`t.test()` and friends). To record results of another kind, write a method for their class:

```r
as_estimation_test.my_test <- function(x, ...)
  list(list(name = "wald", statistic = x$W, distribution = "chi2", df = x$k, p_value = x$p))
```

## Collections

`write_collection()` writes several records as one `estimation-collection` file (spec section
11): a paper's results with where each appears, a session or replication with its timeline,
or a batch of runs. The records are embedded whole and never changed; the locators stay in the
collection.

```r
write_collection(list(baseline = f1, full = f2), "table2.estimation-collection.json",
                 kind = "paper",
                 locators = list("Table 2, col. (1)", list(table = "2", column = "2")),
                 publication = list(citation = list(type = "article-journal", title = "...",
                                                    DOI = "10.1257/...")))
write_collection(fits, "batch.estimation-collection.json", kind = "batch",
                 members = "jsonl")   # records in batch.members.jsonl, one per line
```

Labels default to the list's names. With the `openssl` package installed, each member carries
the SHA-256 of its record's RFC 8785 canonical JSON, which shows which version of the record the
collection holds; without it the hashes are left out (they are optional).

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

estrec doesn't write the core digest (`meta.core_digest`, optional) yet. It now has RFC 8785
canonical JSON (for collections), so the digest needs only `openssl`.

## Not yet

- `feglm`/`fepois` (`glm/0.1`), `lm`/`glm` and other classes through `insight`.
- The `car`, `lmtest` and `marginaleffects` methods are written to those packages' documented
  output but not yet checked against them (they aren't installed where estrec was built).
- Tests: `tests/test-fixest.R` and `tests/test-collection.R` (base R). They validate every
  record and collection when the `estimation` CLI is on `PATH` or `ESTREC_VALIDATOR` names it;
  with `ESTREC_PYTHON` (a Python with `estimation_format`), the collection test also checks that
  estrec's canonical JSON equals the reference implementation's.

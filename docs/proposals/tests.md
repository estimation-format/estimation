# Proposal: a top-level `tests` section

Status: **draft for Ted**, 2026-10-31. Not in the spec or schemas. Once Ted agrees, it
becomes an issue (CONTRIBUTING: core changes start with an issue) and then a schema change.

## Problem

0.1 has no place for a hypothesis test the user asks for after the fit (`wald(fit, "x")`,
Stata `test x = z`, statsmodels `f_test`). And the tests it does record are spread over ten
places, one per profile, each with its own field names:

| Where | Tests | Shape |
|---|---|---|
| `metrics.f_stat`, `f_stat_robust`, `f_fe` (linear-fe) | joint F of the regressors; FE jointly zero | bare scalars: no df, p-value or vcov |
| `metrics.chi2` + `chi2_type` (conditional-logit) | model LR/Wald | scalar + a label |
| `metrics.lr_test` (survival) | LR | — |
| `structures.first_stage` (iv) | first-stage F, weak ID, underidentification, overid, endogeneity | `{name, statistic, p_value, df, df1, df2, distribution}` |
| `structures.ph_test` (survival) | proportional hazards, global and per term | `{statistic, df, p_value}` |
| did `pretrend` | joint pre-trend test | `{name, statistic, df, p_value, distribution}` |
| `structures.small_study` (meta-analysis) | Egger, Begg | tool-specific |
| `parameters[*].smooth` (gam) | smooth-term significance | `{edf, ref_df, statistic, p_value}` |
| `parameters[*].p_value_adjusted` (multiple-testing) | adjusted p for a family | per row |
| `extensions.med2s` | signal test | tool block |

They're nearly the same object under different names. A reader who wants "every test in this
record" has to know every profile.

## Proposal

### 1. One test object in the core schema (`$defs/test`)

```json
{"id": "t1",
 "name": "wald",
 "label": "returns equal across x and x2",
 "hypothesis": {"text": "x = x2", "terms": ["x", "x2"],
                "restrictions": {"R": [[1, -1]], "q": [0], "labels": ["x", "x2"]}},
 "statistic": 4.21, "distribution": "F", "df1": 1, "df2": 39,
 "p_value": 0.047,
 "vcov": {"type": "CRV1", "cluster": ["id"]},
 "method": "wald",
 "source": {"name": "fixest", "version": "0.14.2", "call": "wald(fit, keep = \"x\")"},
 "added": "2026-10-31T14:20:00Z"}
```

- **Required**: `name`, and `statistic` + `distribution` (or a `p_value` alone, for
  resampling tests that have no reference distribution).
- `distribution` with `df`, `df1`, `df2` keeps the flat shape `first_stage` already uses:
  `F` (df1, df2), `chi2` (df), `t` (df), `normal`, or `empirical` for bootstrap and
  permutation tests.
- `hypothesis`: `text` as the user wrote it; `terms` refers to `parameters[*].term`. For a
  linear test, `restrictions` gives R and q (H0: Rb = q), so a reader can recompute it from the
  record's own `parameters` and `vcov`. `alternative` is `two_sided` (default), `greater` or `less`.
- `vcov`: which entry of `structures.vcov` the test used, matched on `type` + `cluster`
  (when omitted: the default one). It matters as much as it does for the SEs: a Wald test
  under iid and under CRV1 can disagree.
- `method`: `wald`, `likelihood_ratio`, `score`, `bootstrap`, `permutation`, ... For a
  resampling test, `resampling` holds the same fields the `resampling` profile uses per row.
- **Single restrictions** (`lincom`, a contrast) MAY also carry `estimate`, `std_error`,
  `conf_low`, `conf_high`. Is that a test or a derived estimate? See question 3.
- **Multiple testing**: `p_value_adjusted` and `family` (the `test_family` of
  `multiple-testing/0.1`), so adjusted p-values work for tests too, not only for parameter rows.
- `source`: the function that computed it, when that isn't the estimator itself (`car`,
  `lmtest`, Stata `test`). `added` is set when the test was added after the record was written.

### 2. A top-level `tests` list (optional)

Every test about the model: the estimator's own (the joint F, first-stage and overid tests)
and those added later. `id`s are unique within the record.

### 3. Rules for adding tests after the fit

A postestimation test doesn't change the results, so it shouldn't need a new record with
`meta.parent` (7.1). Rules:

- `tests` is **append-only**: a tool MAY add entries, and MUST NOT change or remove entries
  that another tool wrote.
- A tool that appends adds a `history` entry (`action: "extended"`, `sections: ["tests"]`).
- `tests` is **outside the core digest** (7.2 covers `meta`, `specification`, `metrics`,
  `parameters`, `structures`). Adding a test then doesn't break the digest, and the digest
  still shows that the results themselves weren't edited.
- A test that compares models (Hausman FE vs RE, `lrtest m1 m2`, cross-equation tests after
  `suest`) carries `records: [<meta.id>, ...]`, the ids of the records it compares. It can
  sit in any of them, or in a collection once collections are specified (section 11).

### 4. The profiles' tests move into `tests` (0.2)

Each profile names its tests in `tests` by `name` instead of in its own location:
`first_stage.per_endogenous[].f_stat` → `{name: "first_stage_f", endogenous: "x", ...}`;
`overid`, `endogeneity`, `pretrend`, `ph_test` (per term: `term`), `small_study` likewise.
Profiles can then say "`tests` holds a `pretrend` test" as a requirement.
`structures.first_stage` keeps what isn't a test (partial R², Shea R²).
`metrics.f_stat` etc. stay as glance-style scalar mirrors (broom's `statistic`, `p.value`), and
the full test goes in `tests`.

## What tools give (to check before the issue)

Probed today: fixest 0.14.2 `wald()` returns `stat`, `p`, `df1`, `df2`, `vcov`, and
`fitstat()` returns the same fields per statistic (`kpr` as 1×1 matrices). The rest comes from
memory and still needs checking:

| Tool | Tests on request | Gives |
|---|---|---|
| R fixest | `wald()`, `fitstat()` | stat, p, df1, df2, vcov label |
| R car / lmtest | `linearHypothesis()`, `waldtest()`, `lrtest()`, `coeftest()` | `anova`-style table: F or Chisq, Df, p |
| R `anova(m1, m2)` | nested-model F/LR | table |
| Stata | `test`, `testparm`, `lincom`, `nlcom`, `lrtest`, `estat ...` | `r(F)`, `r(df)`, `r(df_r)`, `r(chi2)`, `r(p)` |
| statsmodels | `wald_test`, `f_test`, `t_test`, `compare_lr_test` | ContrastResults: statistic, pvalue, df_num, df_denom, distribution |
| pyfixest | `wald_test`, `wildboottest`, `rwolf` | statistic, pvalue |
| linearmodels | `wald_test` | WaldTestStatistic: stat, pval, df, null |

## Questions for Ted

1. **Version.** An optional new top-level member is backward compatible, and 0.1 is still a
   "draft for comment". Amend 0.1, or make this the first change in 0.2? (Under the published-version rule, the
   served 0.1 schemas would have to stay unchanged; that would argue for 0.2.)
2. **Move the profiles' tests (point 4) or leave them?** Moving them gives one place to read,
   but changes ten draft profiles. Leaving them means `tests` is only for user-requested tests.
   Recommended: move them, in 0.2.
3. **Single linear combinations** (`lincom`, marginal-effect contrasts): in `tests`, with
   `estimate`/`std_error`, or in their own section later (`contrasts`, or a derived-quantities
   section next to `marginaleffects`)? Recommended: in `tests` for now. A derived-estimates
   section can come later.
4. **Append-only outside the digest** (point 3): OK? It's the one exception to "a tool MUST NOT
   change a core section".

## In estrec, once agreed

```r
rec <- to_estimation(fit, tests = list(
  wald = fixest::wald(fit, keep = "^x", print = FALSE),   # a fixest test, converted
  "x = x2"                                                # computed from the record's b and V
))
rec <- add_test(rec, "x + x2 = 1", vcov = "hetero")       # append to an existing record
```

A linear restriction given as text is computed from the record's own `parameters` and
`vcov` (W = (Rb − q)'(RVR')⁻¹(Rb − q) / J against F(J, `df_t`)). It then always matches the vcov
the record holds, and any language's writer gives the same answer.

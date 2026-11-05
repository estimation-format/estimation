# Changelog

## Unreleased

- estrec reads records: `read_estimation()` (a record, or a folder of them) and
  `read_collection()` (embedded members or a members file) return records of class
  `estimation_record`, kept as written. `print` gives a quick view; `tidy` and `glance`
  methods, registered on generics, let modelsummary and other broom-based table packages take
  records as they take fitted models. `tidy(vcov = "iid")` and other vcovs in the record
  recompute SEs, tests and intervals; `component =` selects first-stage and other components.
  The writers accept records read back in.
- Disclosure levels (spec 4.9; proposal `docs/proposals/disclosure.md`, Ted 2026-11-05):
  how much a record discloses is the sharer's choice, from 1 (estimates, SEs, p-values,
  intervals, N, df) to 5 (environment, execution, agent, every software component). The core
  schema marks each field with `x-level` (`x-level-if` for software components by role);
  `meta.disclosure.level` declares it. Writers default to 4: language, estimator and writer
  only (the writer also in `history[*].by` and `meta.producer`, so its version can be traced),
  no environment, execution, agent or data locations. At
  level 1 `created` may be a date. Validators: fields above the declared level are errors, and
  withheld expected members are information, not warnings. New history action `reduced`.
- Purpose profiles: a third catalog `kind`, `purpose`, for what a destination needs, with
  `x-min-level`; a floor where the level is a ceiling. None registered yet.
- Validator and tools: `prepare` and `write` take `level` and `purpose`, drop the claims of
  model profiles the level breaks (`profile_not_claimed` in `meta.messages`) and fail when a
  purpose can't be met; `reduce(record, level)` writes a lowered copy as a new record with
  `meta.parent`; `fields_above`, `record_level`, `level_marks`, `path_level`,
  `DEFAULT_LEVEL_MARKS`. `add_test` and `redact` respect the declared level.
- Collections: `estimation-collection/0.1` (spec section 11, `schema/estimation-collection-0.1.json`,
  catalog entry `collection`), a set of records plus what is true of the set. `meta.kind` is
  `paper`, `session`, `replication`, `batch` or `other` and sets what a validator expects: a
  paper's members with locators and the citation; a session's `session` block (its id on every
  member's `provenance.execution.session`) and `events`; a replication's `events` and
  `publication`. Members are the records themselves, embedded or (above 16 MB) in a JSON Lines
  members file beside the collection; each has the record's `meta.id`, an optional `sha256` of
  its RFC 8785 canonical JSON, a `label` and the collection's own `locator`/`locators`, which
  must match the record's publication locators where it has them. Events are
  `{when, type, member, detail, message}` with an open `type` vocabulary. Size limits apply to
  the file and to the collection without its records; each member is checked as a record.
  Redaction covers the collection and its members. Examples: a paper, a session and a
  replication with a members file.
- Validator and tools: `new_collection`, `write_collection`, `read_collection`,
  `validate_collection` (each member validated as a record, under `members[<i>].record`),
  `redact_collection`, `member_sha256`, `add_event`, `iter_members`; `estimation validate`,
  `redact` and `digest` take collections.
- estrec: `write_collection()` (embedded or JSON Lines members; member hashes with the optional
  `openssl` package) and `to_estimation()` for a plain list of fits, which flattens
  `fixest_multi` elements. RFC 8785 canonical JSON in R, checked against the Python reference.
- estrec: fixest `feglm` and `fepois` fits, as `glm/0.1` and `inference/0.1` records: family
  and link, offset, deviance, McFadden pseudo R², AIC/BIC, dispersion, convergence, z tests
  without `df_t`, and fixest's perfect-fit removals split into `singletons` and `separated`
  (checked against the rows fixest kept). `fenegbin` and `femlm` still fail with a clear error.
- Profiles: `ppmlhdfe/0.1` uses `glm/0.1`'s names for the fixed-effect solver inside each IRLS
  step, as fixest `fepois` records do: `itolerance()` is `options.fixef_tolerance` (was
  `inner_tolerance`) and `e(ic2)` is `structures.numerics.fixef_iterations` (was
  `inner_iterations`).
- estrec: `meta.core_digest` on every record when `openssl` is installed (`digest = FALSE` to
  leave it out), equal to the Python reference's. Software purls follow each package's origin
  (`pkg:cran`, `pkg:github/...@<commit>#<subdir>` from remotes/pak metadata, else
  `pkg:generic`); estrec no longer claims to come from CRAN.

- Core: an optional top-level `tests` list (spec 4.8, `$defs/test`) for every hypothesis test
  about the model: the estimator's own, those asked for after the fit, and linear
  combinations. Each test has a `name`, a `statistic` or `p_value`, and optionally a
  `category`, `origin` (`estimation` or `postestimation`), the hypothesis (`text`, `terms`, and
  `R`, `q` for a linear test), the reference distribution and df, the vcov it used, and its
  `source`. `tests` is append-only: any tool may add tests to a record without writing a new
  one. It is outside the core digest. Profiles name tests by `category` and can expect one
  (`x-expected-tests`).
- Profiles: tests move from their own locations to `tests`: iv (`structures.first_stage` keeps
  only the R²s), linear-fe (`metrics.f_stat`, `f_stat_robust`, `f_fe`), glm and
  conditional-logit (`metrics.chi2`, `chi2_type`), did and csdid (`pretrend`), survival
  (`metrics.lr_test`, `structures.ph_test`), meta-analysis (Egger, Begg), sem (`chisq`,
  `chisq_baseline` and their df and p), mixed (`lr_vs_fixed`), causal-ml (grf calibration).
  `multiple-testing/0.1` accepts `p_value_adjusted` on tests. fixest's `kpr` is mapped to
  the Kleibergen-Paap rk Wald F (weak identification), valid only with a non-iid vcov and exact
  identification (checked against ivreg2).
- Validator: checks test ids, restriction shapes, and term and vcov references; warns on a
  missing expected test category. `estimation_format.add_test()` appends a test and logs it in
  `history`.

- Core: optional `parameters[*].scale` (`estimation`, `exponentiated`) and `measure`
  (`odds_ratio`, `hazard_ratio`, ...), so exponentiated estimates are labeled.
- Draft profiles for difference-in-differences: `did/0.1` (standard; csdid, R did, did2s,
  pyfixest did2s), and the tool profiles `did2s/0.1` and `csdid/0.1`, with example records
  and pages in `spec/profiles/`.
- Draft profiles for generalized linear models: `glm/0.1` (standard; Stata logit/probit/
  poisson/glm, ppmlhdfe, R glm, fixest feglm/fepois, statsmodels, pyfixest) and the tool
  profile `ppmlhdfe/0.1`, with example records and pages in `spec/profiles/`.
- Draft standard profile `conditional-logit/0.1` (Stata clogit and xtlogit fe,
  survival::clogit, statsmodels ConditionalLogit), with an example record and a page.
- Draft standard profile `mixed/0.1` (lme4, lmerTest, glmmTMB, Stata mixed and me*,
  statsmodels MixedLM, MixedModels.jl), with an example record and a page.
- Draft standard profile `choice/0.1` (mlogit, logitr, apollo, xlogit, Biogeme, Stata cm*
  and mixlogit), with MNL and mixed-logit example records and a page.
- Draft standard profiles `sem/0.1` (lavaan, semopy, Stata sem) and `mediation/0.1` (R
  mediation, lavaan :=, PROCESS, Stata estat teffects, pingouin, statsmodels Mediation),
  with example records and pages.
- Draft cross-cutting standard profiles `mi/0.1`, `survey/0.1`, `multiple-testing/0.1` and
  `resampling/0.1`, which combine with a model's own profile, with example records and pages.
- `mediation/0.1`: two-stage (IV) mediation (`instruments`, `instrumented`), the Aroian
  method and controlled direct effects; mappings for `mediate_tsls`, `ivmediate` and StataNow
  `mediate`.
- Draft standard profile `survival/0.1` (R survival and cmprsk, lifelines, scikit-survival,
  statsmodels PHReg, Stata stcox/streg/stcrreg), with Efron and Breslow Cox examples and a page.
- `mediation/0.1`: several predictors, `total_indirect`, and a mapping for `indirect_boot`.
- Draft tool profile `med2s/0.1` (two-stage DiD mediation), with an `extensions.med2s` block,
  a shape example and a page.
- Draft standard profile `meta-analysis/0.1` (metafor, meta, statsmodels, Stata meta), with an
  example record and a page.
- Draft standard profiles `predictive/0.1` (scikit-learn, XGBoost, ranger, tidymodels, mlr3)
  and `causal-ml/0.1` (DoubleML, EconML, grf), with example records and pages.
- Draft standard profiles `gam/0.1` (mgcv, pyGAM, statsmodels GLMGam) and `bayesian/0.1` (brms,
  rstanarm, Stan, PyMC/ArviZ, Stata bayes), with example records and pages.
- `mediation/0.1`: StataNow `mediate` and `ivmediate` mapped from their help files (pure
  indirect, total direct and potential-outcome-mean effects; interaction and treatment type;
  `ivmediate`'s two first-stage F statistics).
- Stata mappings checked against the help files for `glm`, `clogit`, `cmclogit`,
  `cmmixlogit`, `cmmprobit`, `mixed`, `stcox`, `streg` and `bayes`. `choice/0.1`: Stata stores
  the base alternative as `e(i_base)` (`cmmixlogit`: `e(base)`), not `e(basealt)`, and the
  integration defaults (Hammersley points, a sample-size-dependent count) are now mapped.
  `mixed/0.1`: `e(N_g)` and `e(g_*)` are matrices by level. `survival/0.1`: `streg`'s
  ancillary parameters and `e(frm2)`, and `stcox`/`streg` `e(cmd)` vs `e(cmd2)`.
- Second help-file pass (`logit`, `melogit`, `meglm`, `mi estimate`, `svy`, `svyset`, `sem`,
  `estat gof`, `bootstrap`, `meta summarize`, `stcrreg`, `stcox` postestimation, `bayesmh`,
  `bayesstats grubin`): `mi/0.1` maps RVI to `e(rvi_mi)`, not `e(riv_mi)`; Stata `bootstrap`
  seeds with `rseed()`; `estat phtest` per-term results are the `r(phtest)` matrix; `stcrreg` has no `ties()` option and always reports robust SEs; added
  `bayesmh` and `meta summarize` stored results. Documentation-only R mappings checked against
  source on GitHub (base R `glm` and `p.adjust`, rstanarm/rstan, cmprsk, ri2, caret, tidymodels,
  mlr3): rstanarm has no pathfinder, its `adapt_delta` default is 0.95, and caret's
  `trainControl()` defaults to 25 bootstrap resamples.
- Format `estimation/0.1` (draft) and the `inference/0.1`, `linear-fe/0.1`, `iv/0.1` and
  `dfeols/0.1` profiles, moved from the dfeols repository
  (https://github.com/jemather/dfeols, `src/dfeols/schema/` at a33a767) into their own
  repository. Schema `$id`s now point to `https://estimation-format.github.io/estimation/schema/`.
- `estimation-format` 0.1.0.dev0: the reference validator, writer and redactor, from
  `dfeols.estimation`. The built-in fallback checks cover the standard profiles only; tool
  profiles are checked through their schemas.
- `converters/`: worked converters from pyfixest, fixest (R) and reghdfe (Stata) to
  `linear-fe/0.1` records, with `tests/test_converters.py` comparing the tools on one panel.
- `linear-fe/0.1` (draft): `sigma` defined as sqrt(RSS / (N - K)), with pyfixest `_rmse`
  (sqrt(RSS / N)) recorded as `{value, definition}`; pyfixest has no residual df (`_dfd` is
  the Wald denominator df); reghdfe per-cluster counts are `e(N_clust#)`.
- `linear-fe/0.1` (draft): `metrics.n_singletons` is expected, not required (pyfixest and
  fixest don't store it). The validator now warns for a missing `x-expected` field of a
  claimed profile (also `iv/0.1` `structures.first_stage`); `expected_paths()` lists them.
- `write`/`prepare`: `redact_identifying` also takes a list of paths, so a tool can redact its
  own extension's fields whatever profiles the record claims.

# Changelog

## Unreleased

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

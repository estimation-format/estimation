# Changelog

## Unreleased

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

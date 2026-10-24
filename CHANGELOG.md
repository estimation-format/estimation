# Changelog

## Unreleased

- Format `estimation/0.1` (draft) and the `inference/0.1`, `linear-fe/0.1`, `iv/0.1` and
  `dfeols/0.1` profiles, moved from the dfeols repository
  (https://github.com/jemather/dfeols, `src/dfeols/schema/` at a33a767) into their own
  repository. Schema `$id`s now point to `https://estimation-format.github.io/estimation/schema/`.
- `estimation-format` 0.1.0.dev0: the reference validator, writer and redactor, from
  `dfeols.estimation`. The built-in fallback checks cover the standard profiles only; tool
  profiles are checked through their schemas.

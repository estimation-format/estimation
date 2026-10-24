# Profile `inference/0.1`

Status: draft. Schema: [`schema/profiles/inference-0.1.json`](../../schema/profiles/inference-0.1.json).
Kind: standard. Surveyed: R `lm` and estimatr, statsmodels, Stata `regress`.

Records of models that report estimates with standard errors. The other inference profiles
(`linear-fe`, `iv`) build on it.

## Requirements

A record claiming `inference/0.1` MUST have:

- in `parameters`, on every row that is not `dropped`: `estimate`, `std_error` and `p_value`;
- `metrics.nobs` and `metrics.df_residual`;
- a default vcov in `structures.vcov`: the one marked `default: true`, or the only one. It
  MUST have `type` and `ssc` with at least `convention`. Two vcovs both marked default are an
  error.

## Vocabulary

- `structures.vcov[*].type`: `iid`, `HC0` to `HC3`, `CRV1`, `CRV3`, `twoway`/`multiway`,
  `HAC`, `DK` (recommended values; any string is allowed).
- `structures.vcov[*].ssc` (small-sample correction): `convention` names the tool whose
  convention the correction reproduces (`"fixest"`, `"reghdfe"`, `"stata"`, `"R lm"`,
  `"linearmodels debiased=True"`); `formula`, `factors` and `K_counts` write it out when the
  writer has them. These factors are the most common source of standard-error differences
  between tools, which is why `convention` is required.
- `structures.vcov[*].df_t`: the df used for t tests and confidence intervals (many tools use
  G − 1 under clustering), which can differ from `metrics.df_residual`.
- `metrics.df_residual` is the residual df as the tool reports it. When that is not the
  textbook N − K (minus absorbed levels), writers SHOULD say what it is with
  `{value, definition}`.

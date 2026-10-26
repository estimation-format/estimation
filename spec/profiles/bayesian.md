# Profile `bayesian/0.1`

Status: draft. Schema: [`schema/profiles/bayesian-0.1.json`](../../schema/profiles/bayesian-0.1.json).
Kind: standard. Builds on the core only.

Bayesian models fit by MCMC or approximate inference. Surveyed 2026-10-25: from source, brms
2.23.2 (paul-buerkner/brms @ e5f1966), PyMC 6.3.2 and ArviZ 1.3.0; rstanarm, CmdStanPy, Bambi
and Stata `bayes`/`bayesmh` from documentation. The model's own structure is described by its
other profile where one fits (a Bayesian mixed model also claims [`mixed/0.1`](mixed.md) if it
meets it); this profile covers what Bayesian inference adds.

## Requirements

- `meta.estimator.method`: `nuts`, `hmc`, `mh`, `gibbs`, `slice`, `smc`, `advi`,
  `fullrank_advi`, `pathfinder`, `laplace`, `inla`.
- `specification.priors`: **every** prior in effect, `{parameter, distribution, default,
  data_dependent}`. Default priors count: brms and rstanarm scale several of theirs to the
  data.
- For sampling methods: `specification.sampling` with `chains`, `draws` (retained per chain),
  `warmup` and `seed` (`null` when none was set).
- On every row that isn't dropped: `estimate` and a `posterior` object with `point` (what
  `estimate` is), `sd`, `ci_low`, `ci_high`, `ci_prob` and `ci_kind`.
- `metrics.nobs`.

The rows carry no `std_error`, `statistic` or `p_value`.

## Defaults that change what is reported

| | brms | rstanarm | PyMC | ArviZ `summary` | Stata `bayes` |
|---|---|---|---|---|---|
| Chains | 4 | 4 | **max(2, min(4, CPU count))**: depends on the machine | | 1 |
| Draws per chain (after warmup) | 1000 (`iter` 2000) | 1000 | 1000 | | 10000 |
| Warmup | 1000 | 1000 | 1000 (`tune`) | | 2500 (`burnin`) |
| Seed | random (`seed = NA`) | random | random (`random_seed = None`) | | random |
| `target_accept` / `adapt_delta` | 0.8 | varies by model | 0.8 | | — |
| Point summary | mean | **median** (`MAD_SD` as its SD) | | mean | mean |
| Interval | 95% equal-tailed | 90% (`posterior_interval`) | | **89% equal-tailed** (1.x; 94% HDI in 0.x) | 95% equal-tailed (`hpd`) |

Two results from the same posterior draws can differ in their reported point estimate, SD and
interval only because of these summaries; `point`, `ci_prob` and `ci_kind` are therefore
required on every row.

## Convergence and diagnostics

Per row (`posterior`): `rhat`, `ess_bulk`, `ess_tail`, `mcse_mean`, `mcse_sd`, plus `mean`,
`median`, `mad`, `prob_positive`. brms: `Rhat`, `Bulk_ESS`, `Tail_ESS` (rank-normalized);
ArviZ: `r_hat`, `ess_bulk`, `ess_tail`, `mcse_*`; Stata: `ESS`, `MCSE`, and R-hat from
`bayesstats grubin` when there are several chains.

`structures.numerics` (expected for MCMC): `n_divergent`, `n_max_treedepth`, `ebfmi_min`,
`max_rhat`, `min_ess_bulk`. Divergent transitions are the first thing to check when two runs
disagree.

Model comparison: `metrics.elpd_loo` (`{value, se, p_loo, n_bad_pareto_k}`), `waic`, `dic` and
`log_marginal_likelihood` (Stata `bayesstats ic`), `bayes_r2`, `acceptance_rate` (Stata
`e(arate)`).

## Example

[`schema/examples/bayesian.estimation.json`](../../schema/examples/bayesian.estimation.json): a
real PyMC logistic regression on the Spector-Mazzeo data (the same data as the `glm/0.1` logit
example), NUTS with 4 chains of 1000 draws, summarized by ArviZ with its default 89%
equal-tailed intervals; no divergences, all R-hat 1.00.

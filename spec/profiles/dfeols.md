# Profile `dfeols/0.1`

Status: draft. Schema: [`schema/profiles/dfeols-0.1.json`](../../schema/profiles/dfeols-0.1.json).
Kind: tool. Maintainer: the [dfeols](https://github.com/jemather/dfeols) project.
`x-extends`: `linear-fe/0.1`, with no deviations.

The first worked tool profile: records from dfeols, a sharded, distributed estimator for
linear models with high-dimensional fixed effects. It shows how a tool profile builds on a
standard one and defines its own extension block.

## Requirements

Everything [`linear-fe/0.1`](linear-fe.md) requires (the profile includes those rules, so it
has no departures to declare), plus an `extensions.dfeols` block with `schema: "dfeols/0.1"`.

## The `extensions.dfeols` block

What only dfeols has:

- `shards`: shard folder, prep version, partition key, target rows, shard count, a hash of
  the shard metadata. Results must not depend on the partition, but it is the first thing to
  check when they do.
- `row_key`: a hash of the indices of the rows used, combined shard by shard, so two runs can
  be checked for an identical sample without storing rows.
- `absorption`: per fixed effect, the method (`local`, `crossing_dense`, `crossing_sparse`,
  `crossing_iterate`: conjugate gradient on the crossing-FE coefficients)
  and whether it is nested in the partition.
- `demeaning`: per-shard iterations (max, median), the worst shard's final change, timing of
  each round; the persisted demeaned-data key when the run came from a session.
- `dask`: scheduler address, worker specs, the resolved launch profile.
- `estimate`: the time estimate shown at submission.
- `replay`: the `dfeols.fit` call with every argument explicit, and the dfeols commit it
  needs, so the run can be repeated and compared against the record.

`shards.folder`, `dask.scheduler_address` and the site details in `dask.profile`
(`account`, `project`, `scratch`, `source`, `prologue`, `env`) are marked `x-identifying`.

## Example

[`schema/examples/dfeols-linear-fe.estimation.json`](../../schema/examples/dfeols-linear-fe.estimation.json).

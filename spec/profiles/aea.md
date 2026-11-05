# Profile `aea/0.1`

Status: draft. Schema: [`schema/profiles/aea-0.1.json`](../../schema/profiles/aea-0.1.json).
Kind: purpose (spec 9.1). Minimum disclosure level: **4** (`x-min-level`).

Records of results in a replication package for a journal of the American Economic
Association. The policy is about the package as a whole (its README, data, code and deposit).
A record describes one result in it, so this profile covers only the policy's rules that
concern a single result. The README, deposit format, rights statements, master script and
data formats belong to the package.

## Sources

Read 2026-11-05:

- [AEA] *Data and Code Availability Policy*, https://www.aeaweb.org/journals/data/data-code-policy,
  revised February 2026. Its rules are numbered by the Data and Code Availability Standard
  (DCAS).
- [Template] Social Science Data Editors, *template README*,
  https://social-science-data-editors.github.io/template_README/template-README.html.
- [Prepare] AEA Data Editor, *Preparing your files for verification*,
  https://aeadataeditor.github.io/aea-de-guidance/preparing-for-data-deposit.html.

## Requirements

A record claiming `aea/0.1` MUST have:

| Rule | Source |
|---|---|
| `publication.locator` (or each of `locators`) with `label` and one of `table`, `figure`, `page` or `section` | [AEA] DCAS #13: the README maps each program to its outputs and each output to the paper's exhibits; [Template] "List of tables and programs" |
| on every row of `parameters` that isn't `dropped`: `estimate`, and `std_error` or both `conf_low` and `conf_high` | [Prepare]: the package reproduces "the tables and figures, as well as any in-text numbers" |
| `meta.core_digest` | [Prepare]: re-runs should give results that are "numerically identical"; the digest shows whether a record's results were edited after the run |
| `provenance.software`: a `language` and an `estimator` component, each with `version` | [AEA] DCAS #13: "Specify software versions"; [Template] "In all cases, list the version you used" |
| `provenance.data`: at least one input, each with `name` | [AEA] DCAS #1: the data availability statement covers where the data come from |
| a seed that was set (not null) when the record also claims `resampling/0.1` (`specification.resampling.seed`), `bayesian/0.1` (`specification.sampling.seed`) or `causal-ml/0.1` (`specification.cross_fitting.seed`) | [Template] "Controlled Randomness": a deterministic seed, "set once, and not use a time-stamp" |

Expected (validators warn when missing):

| Field | Why expected rather than required |
|---|---|
| `specification.program` (`{path, line, sha256}`, path within the package) and `specification.call` | [Template] wants "the program (and possibly the line number)"; not every writer knows the script it runs in |
| `provenance.data[*].publication` (a data citation) | [AEA] DCAS #6: cite all data used; data the authors created themselves have no citation |
| `provenance.data[*].checksum` | Not in the policy, but it is how a replicator confirms they have the same data |
| `publication.citation`, `status` and `replication_package` | Before acceptance the paper may have no DOI and the package no deposit |

Recommended: a `lock` pointer (`format` and `sha256`) on the language component. The README
lists every package ([Template] "All packages should be listed"); at level 4 the record
names the language, estimator and writer, and a lock file's hash commits to the full
environment without listing it. The validator can't single out one component to warn
about, so this is a recommendation only.

## What it leaves out

- Running time, hardware and storage ([AEA] DCAS #13): the README gives them per package. In
  a record they are level 5 (`provenance.execution`, `environment`).
- Every loaded package: the README lists them; in a record they are level 5.
- The README itself, the deposit format, rights and access statements, and the master
  script.

## Example

[`schema/examples/aea.estimation.json`](../../schema/examples/aea.estimation.json): an
illustrative paper and data set (not a real study), written with
`prepare(record, purpose="aea/0.1")` from a fuller record, so level-5 fields (a dependency,
the lock's path, the environment, the user and host, the data's location) were left out.

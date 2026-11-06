# Profile `dcas/0.1`

Status: draft. Schema: [`schema/profiles/dcas-0.1.json`](../../schema/profiles/dcas-0.1.json).
Kind: purpose (spec 9.1). Minimum disclosure level: **4** (`x-min-level`).

Records of results in a replication package for a journal that follows the Data and Code
Availability Standard (DCAS). The standard's site lists 19 endorsing journals: the journals
of the American Economic Association (the AER, AER: Insights, the four AEJs, the JEL and the
JEP), the Canadian Journal of Economics, Econometrica, the Econometrics Journal, Economic
Inquiry, the Economic Journal, the Journal of Political Economy, the Journal of the European
Economic Association, Quantitative Economics, the Review of Economic Studies, the Review of
Financial Studies and Theoretical Economics. It notes that "individual journal policies may
differ slightly"; this profile follows the standard, not any one journal's version of it.

The standard is about the package as a whole (its README, data, code and deposit). A record
describes one result in it, so this profile covers only the rules that concern a single
result. The README, deposit, licence, rights statements, master script and data formats
belong to the package.

## Sources

Read 2026-11-05 and 2026-11-06:

- [DCAS] *Data and Code Availability Standard*, version 1.0, 2022-12-15,
  https://datacodestandard.org/, doi:10.5281/zenodo.7436134. Rules #1-#16. Endorsing
  journals: https://datacodestandard.org/journals/.
- [Template] Social Science Data Editors, *Template README for social science replication
  packages*, version 1.2.rc1,
  https://github.com/social-science-data-editors/template_README/blob/release-candidate/templates/README.md.
  DCAS #13 asks for a README that follows it. The quotes below are also in the published version
  (https://social-science-data-editors.github.io/template_README/), except the seed
  checkbox, which is new in 1.2.rc1.
- [AEA] AEA *Data and Code Availability Policy*, https://www.aeaweb.org/journals/data/data-code-policy,
  revised February 2026, and the AEA Data Editor's *Preparing your files for verification*,
  https://aeadataeditor.github.io/aea-de-guidance/preparing-for-data-deposit.html: one
  journal's statement of the standard, used where it says more than the standard does.

## Requirements

A record claiming `dcas/0.1` MUST have:

| Rule | Source |
|---|---|
| `publication.locator` (or each of `locators`) with `label` and one of `table`, `figure`, `page` or `section` | [DCAS] #13: the README explains "how to reproduce the research results"; [Template] "List of tables and programs" |
| on every row of `parameters` that isn't `dropped`: `estimate`, and `std_error` or both `conf_low` and `conf_high` | [DCAS] #8: programs producing the computational results are included; [Template] "List of tables and programs": "All numbers provided in text in the paper", "All tables and figures in the paper" |
| `meta.core_digest` | [AEA] (*Preparing your files*): re-runs should give results that are "numerically identical"; the digest shows whether a record's results were edited after the run |
| `provenance.software`: a `language` and an `estimator` component, each with `version` | [DCAS] #13: "listing all software and hardware dependencies"; [Template] "In all cases, list the version *you* used" |
| `provenance.data`: at least one input, each with `name` | [DCAS] #1: a data availability statement detailed enough that an independent researcher can obtain the data |
| a seed that was set (not null) when the record also claims `resampling/0.1` (`specification.resampling.seed`), `bayesian/0.1` (`specification.sampling.seed`) or `causal-ml/0.1` (`specification.cross_fitting.seed`) | [Template] "Controlled Randomness": a deterministic seed, "set once, and not use a time-stamp" |

Expected (validators warn when missing):

| Field | Why expected rather than required |
|---|---|
| `specification.program` (`{path, line, sha256}`, path within the package) and `specification.call` | [Template] "List of tables and programs": "identifying the program (and possibly the line number) where a figure is created"; 1.2.rc1 also asks where the seed is set ("Random seed is set at line ___ of program ___"). Not every writer knows the script it runs in |
| `provenance.data[*].publication` (a data citation) | [DCAS] #6: "All data used in the paper are cited"; data the authors created themselves have no citation |
| `provenance.data[*].checksum` | Not in the policy, but it is how a replicator confirms they have the same data |
| `publication.citation`, `status` and `replication_package` | Before acceptance the paper may have no DOI and the package no deposit |

Recommended: a `lock` pointer (`format` and `sha256`) on the language component. The README
lists every package ([Template] "All packages should be listed"); at level 4 the record
names the language, estimator and writer, and a lock file's hash commits to the full
environment without listing it. The validator can't single out one component to warn
about, so this is a recommendation only.

## What it leaves out

- Running time, hardware and storage ([DCAS] #13, "including the expected run time"): the README gives them per package. In
  a record they are level 5 (`provenance.execution`, `environment`).
- Every loaded package: the README lists them; in a record they are level 5.
- The README itself, the deposit format, rights and access statements, and the master
  script.

## Example

[`schema/examples/dcas.estimation.json`](../../schema/examples/dcas.estimation.json): an
illustrative paper and data set (not a real study), written with
`prepare(record, purpose="dcas/0.1")` from a fuller record, so level-5 fields (a dependency,
the lock's path, the environment, the user and host, the data's location) were left out.

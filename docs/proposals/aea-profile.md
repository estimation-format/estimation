# Proposal: a purpose profile for AEA journals

Status: **draft for review** (2026-11-05). The first purpose profile (spec 9.1): what a record
needs so that the AEA Data Editor, or an author preparing a replication package, can use it.

## Sources

Read 2026-11-05:

- [AEA] *Data and Code Availability Policy*, https://www.aeaweb.org/journals/data/data-code-policy,
  revised February 2026. Its rules are numbered by the Data and Code Availability Standard
  (DCAS #1-#16).
- [Template] Social Science Data Editors, *template README*,
  https://social-science-data-editors.github.io/template_README/template-README.html (no
  version or date on the page).
- [Prepare] AEA Data Editor, *Preparing your files for verification*,
  https://aeadataeditor.github.io/aea-de-guidance/preparing-for-data-deposit.html (the page
  shows two dates, 2021-04-08 and 2023-09-07).

## What the policy asks for, and where a record fits

The policy is about the **replication package**: its README, data, code and deposit. A record
describes **one result** in it. So the profile covers only the policy's rules that concern a
single result, and leaves the rest (deposit format, README as PDF, rights statements, the
master script, data formats) to the package.

| Policy rule | Source | In the record | Level |
|---|---|---|---|
| Map each output to the exhibit in the paper: "Figure/Table #, Program, Line Number, Output file" | [AEA] README, DCAS #13; [Template] "List of tables and programs" | `publication.locator` (table, column, ..., `label`) | 1 |
| Reproduce tables, figures **and in-text numbers**; no manual entry; re-runs "numerically identical" | [Prepare] | `parameters` with `estimate`, `std_error`; `meta.core_digest` | 1 |
| Cite all data used | [AEA] DCAS #6; [Prepare] | each `provenance.data[*]` input with a `publication.citation` | 4 |
| Say where data come from and how to get it | [AEA] DCAS #1 | `provenance.data[*]`: `name`, `version`, `source` | 4 |
| Software and versions, "list the version you used" | [AEA] DCAS #13; [Template] "Software Requirements" | `provenance.software`: the language and the estimator, each with `version` | 4 |
| Programs that produce estimation results | [AEA] DCAS #7-#9 | `specification.call` (the command as run) | 3 |
| Deterministic seed, "set once, not a time-stamp" | [Template] "Controlled Randomness" | for resampling and simulation estimators, the seed in `specification.options` | 3 |

## Proposed rules (`aea/0.1`, `x-min-level: 4`)

Required:

1. `publication.locator` (or `locators`), each with `label`, and with `table` or `figure`
   (or `page` or `section`, for an in-text number).
2. `parameters[*]` with `estimate` and `std_error` (or an interval) on every row that isn't
   `dropped`.
3. `meta.core_digest`.
4. `provenance.software`: a `language` component and an `estimator` component, each with
   `version`.
5. `provenance.data`: at least one input, each with `name`.

Expected (a warning when missing):

6. `provenance.data[*].publication.citation` (DCAS #6): data the authors created themselves
   have no citation, so it can't be required.
7. `provenance.data[*].checksum`: not in the policy, but it is how a replicator confirms they
   have the same data; the policy's "numerically identical" depends on it.
8. `specification.call`.
9. `publication.citation` and `status`: before acceptance the paper may have no DOI.
10. `publication.replication_package` (`{doi, url}`), once deposited.

## Questions for Ted

1. **Program and line.** The template wants the program (and line) that produces each
   exhibit. The record's only field for that is
   `provenance.execution.invocation.script_path`, which is identifying and level 5, so the
   profile would need level 5. Add a non-identifying field for the program's path *within the
   package* (e.g. `specification.program: {path, line, sha256}`, level 3)? Recommended.
2. **All packages.** The template says "All packages should be listed... list the version you
   used". The README carries that list; the record at level 4 names the language, estimator
   and writer. Keep the profile at level 4, or require level 5 (every loaded package)?
   Recommended: level 4, with a software `lock` pointer as expected rather than required.
3. **Seeds.** Require a seed in `specification.options` only when the record also claims
   `resampling/0.1`, `bayesian/0.1` or `causal-ml/0.1`? A profile can express that with
   `if`/`then`.
4. **Name.** `aea/0.1`, or `dcas/0.1` after the shared standard? The AEA numbers its rules by
   the DCAS, which suggests other journals use the same standard; I haven't checked which, so
   I'd start with `aea/0.1` and generalise once that's confirmed.
5. **Running time and hardware** (DCAS #13) are per package in the README, and in a record they
   are level 5 (`execution`, `environment`). Leave them out of the profile? Recommended.

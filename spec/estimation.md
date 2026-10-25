# The `estimation` format, version 0.1

**Status: draft for comment.** Version 0.1 may still change in incompatible ways. Comments
are welcome as issues at https://github.com/estimation-format/estimation. The first stable
version will be `estimation/1`.

This document, the JSON Schemas in [`schema/`](../schema/) and the
[profiles](profiles/) together define the format. Where this document and a schema
disagree, that is a bug: please report it.

## 1. Introduction

An `estimation` record is a JSON file that describes **one estimation run**: what was
estimated, what came out, and how and where it ran. It works for any software and any kind
of model: base R `lm`, fixest, reghdfe, statsmodels, pyfixest, a random forest.

A record serves three uses:

1. **Reading and reporting** results: tables, plots, regression summaries.
2. **Explaining a discrepancy** between two runs or two tools *without rerunning them*.
   Comparing two records should show whether the rows, options, small-sample correction,
   convergence, software, environment or data differ.
3. **Reproducing** a run with confidence.

A record stays **small**: results and metadata, never per-row data. Large outputs are linked
as attachments, not embedded.

The format has a small **core** that every producer can fill, and **profiles** that add
the rules for a kind of model (for example linear models with fixed effects) or for one
tool's records. Tools that handle a record later can add their own **extension** blocks.

### 1.1 Conventions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in BCP 14 ([RFC 2119], [RFC 8174]) when, and only when, they
appear in all capitals, as shown here.

Paths to fields are written with dots (`provenance.execution.scheduler`); `[*]` means every
item of a list and `*` every key of an object.

### 1.2 Terms

| Term | Meaning |
|---|---|
| record | one `estimation` JSON document, describing one run |
| run | one estimation call at one time |
| producer | the software that estimated the model |
| writer | the code that writes the record: the producer itself, or a converter (e.g. one that reads Stata's `e()`) |
| reader | any code that reads records |
| validator | a reader that checks a record against this specification, the core schema and the profiles the record claims |
| profile | a named, versioned set of extra rules for a kind of record (section 9) |
| extension | a block under `extensions`, owned by the tool that wrote it (section 7) |
| catalog | the registered list of the core schema and the profiles (section 9.3) |

## 2. Encoding

- A record MUST be a single JSON object ([RFC 8259]) encoded in UTF-8.
- A record file SHOULD be named `<name>.estimation.json`.
- Numbers SHOULD be written with enough precision to round-trip a 64-bit float (17
  significant digits).
- JSON has no non-finite numbers. Where the format expects a number, the strings `"NaN"`,
  `"Inf"` and `"-Inf"` MUST be used for them, and bare `NaN` or `Infinity` tokens MUST NOT
  appear.
- An **absent** key means the producer does not record that quantity. **`null`** means the
  quantity applies but was not computed. Writers MUST NOT use one for the other.
- Times MUST be in UTC, as ISO 8601 / [RFC 3339] timestamps (`2026-10-24T15:02:11Z`). A
  local time zone, when relevant, is recorded separately (`provenance.execution.timezone`).
- Values are **resolved, not as typed**: an option is recorded with the value in effect,
  defaults included. A later change of a tool's default then cannot change what an existing
  record means.

## 3. Structure

A record has the following top-level members. Each is **required**, **expected** or
**optional**:

- A record without a **required** member is invalid.
- A record without an **expected** member is valid, but validators MUST warn, and writers
  SHOULD include the member whenever they can fill it.
- **Optional** members are used when they apply.

| Member | Status | Content |
|---|---|---|
| `schema` | required | the format version, `"estimation/0.1"` |
| `meta` | required | identity and type of the run (4.1) |
| `parameters` | required | one row per reported parameter (4.4) |
| `metrics` | expected | named scalar results (4.3) |
| `specification` | expected | what was asked for (4.2) |
| `provenance` | expected | software, environment, execution, data (4.6) |
| `structures` | optional | named complex results: vcov, fixed effects, ... (4.5) |
| `publication` | optional | where the result appears in a paper (5) |
| `validation` | optional | the same model in other software, and comparisons (6) |
| `attachments` | optional | links to large side files (8) |
| `extensions` | optional | blocks added by tools, one per namespace (7) |
| `history` | optional | every tool that created, extended or redacted the record (7) |

Writers MUST NOT add other top-level members; tool-specific content belongs in
`extensions`. Validators SHOULD warn about unknown top-level members.

A record from base R `lm` and one from a distributed fixed-effects estimator have the same
shape; the second is just fuller. Section 12 shows a minimal record.

## 4. Result sections

### 4.1 `meta` (required)

| Field | Status | Content |
|---|---|---|
| `id` | required | a UUID ([RFC 9562]) identifying this record |
| `created` | required | when the record was written |
| `status` | required | `"ok"`, `"warning"` or `"failed"`. A failed run SHOULD still produce a record with what it knows |
| `parent` | optional | the `id` of the record this one derives from (the same model with a new vcov, for example) |
| `messages` | optional | list of `{level, code, message, source}`: collinear terms dropped, slow convergence, few clusters, singletons removed |
| `estimator` | optional | `{family, method, ...}`, e.g. `{family: "linear", method: "ols"}`, `{family: "glm", method: "mle", distribution: "binomial", link: "logit"}`, `{family: "ensemble", method: "random_forest"}` |
| `responses` | optional | the dependent variable(s) |
| `profiles` | optional | the profiles the record claims to follow, e.g. `["linear-fe/0.1"]` (section 9) |
| `title`, `tags`, `notes` | optional | user labels and free text |
| `producer` | optional | `{name, version}` of the writer, when it is not the estimating software (a converter) |
| `core_digest` | optional | integrity check over the result sections (7.2) |

`estimator.family` and `estimator.method` have a recommended vocabulary (in the schema), but
any string is valid, so a new kind of model needs no change to the format.

### 4.2 `specification` (expected)

What was asked for, in the estimating software's own terms, fully resolved:

- `call`: the command as written (`feols(y ~ x | fe, data)`, `reghdfe y x, absorb(fe)`).
- `formula`: `{text, syntax}`, where `syntax` names the formula language (`R`, `fixest`,
  `patsy`, `stata`, ...).
- `terms`: the expanded regressors in model order; `factor_terms` with their levels and
  reference level.
- `weights`: `{variable, type}` (`analytic`, `frequency`, `probability`), or `null`.
- `fixed_effects`, `endogenous`, `instruments`, `clusters`: as specified.
- `sample`: the restriction as written, plus `rows_input` and drop counts by reason (missing
  per variable, singletons, zero weights, other). The number of rows used is
  `metrics.nobs`.
- `state`: settings in force from *outside* the call that change results without
  appearing in it: an active filter, weight or split (SPSS); `xtset`/`tsset`, `if`/`in`, the
  random-number seed (Stata); R `options()` that change estimates; user-defined missing-value
  codes and how they were treated.
- `options`: every option with its effective value: tolerances, algorithms, seeds,
  hyperparameters.

### 4.3 `metrics` (expected)

An object of named scalars. `nobs` (rows used) applies to nearly every estimator; the rest
depend on it (`r2`, `aic`, `log_lik`, `auc`, `mse`, ...).

- Names SHOULD follow broom's `glance` where one exists. The core schema registers
  recommended names and their definitions, and profiles add more, so that a name means the
  same thing in any two records. Unregistered names are allowed.
- A metric is a number (or a non-finite string, section 2), a string, a boolean, `null`, or
  an object `{value, definition, ...}` when the writer needs to say exactly what it
  computed (for example a residual df that is not the textbook one).
- `conf_level` records the confidence level of `parameters[*].conf_low`/`conf_high`.

### 4.4 `parameters` (required)

A list of rows, one per parameter the model reports. Each row MUST have `term`; the other
columns depend on the estimator:

- **Inference**: broom `tidy` names: `estimate`, `std_error`, `statistic`, `p_value`,
  `conf_low`, `conf_high`, computed from the default vcov (4.5).
- **Machine learning**: `importance`, `rank`, and so on.
- **Models with several parts**: `response` (which outcome), `component` (e.g.
  `first_stage`, `zero_inflation`, `random`), `group` (for random-effect terms).
- `dropped`: `null`, `"collinear"` or `"reference"`. Dropped terms stay in the list as rows,
  so the term list is complete.

Rows are the model's reported parameters. Per-level estimates (fixed-effect coefficients,
BLUPs) are not parameters in this sense: they MUST go in an attachment (section 8).

#### 4.4.1 Term names

`term` is **verbatim**: the name exactly as the producing software reports it,
transformations included (`log(price)`, `i(year, ref = 2000)::2005`, `2005.year`). Writers
MUST NOT reinterpret it.

`canonical` is OPTIONAL and RECOMMENDED: a standard form that lets records from different
tools be matched and tabulated together. It is `{name, factors}`:

```json
{"term": "i(year, ref = 2000)::2005",
 "canonical": {"name": "year2005",
               "factors": [{"variable": "year", "level": "2005", "reference": "2000"}]}}
{"term": "c.price#c.weight",
 "canonical": {"name": "price:weight", "factors": [{"variable": "price"}, {"variable": "weight"}]}}
{"term": "2005.year#c.x",
 "canonical": {"name": "2005.year#c.x",
               "factors": [{"variable": "year", "level": "2005"}, {"variable": "x"}]}}
```

- `factors` is the definition, and matching across tools MUST use it. `name` is a readable
  rendering. The constant has `name: "(Intercept)"` and no factors; every other term has at
  least one factor.
- `name` follows R's `model.matrix` naming: `(Intercept)`, a variable followed by its level
  (`year2005`), `:` between interacted terms. That concatenation can be ambiguous (`year2005`
  could be variable `year2`, level `005`); `factors` resolves it.
- One exception: **factor × continuous interactions use Stata's form** (`2005.year#c.x`),
  which is clearer than R's (`factor(year)2005:x`).
- Levels and transformations stay as the tool reports them (codes or labels, `log(x)` as
  written). A factor MAY add `level_label` or `transform` when the writer knows them.
- Interaction order is kept as specified, in both `term` and `name`. Matching on `factors`
  ignores order.
- Models with absorbed fixed effects need no constant row. A tool that reports one (reghdfe's
  `_cons`) includes it, and `structures.fixed_effects[*].constant_reported` says so.

How tools spell the same term:

| Term | R `lm` | fixest | Stata | patsy (statsmodels, pyfixest) | canonical `name` |
|---|---|---|---|---|---|
| constant | `(Intercept)` | `(Intercept)` | `_cons` | `Intercept` (statsmodels `const`) | `(Intercept)` |
| factor level | `factor(year)2005` | `year::2005` | `2005.year` | `C(year)[T.2005]` | `year2005` |
| base level | (not shown) | (not shown) | `2000b.year` | (not shown) | row with `dropped: "reference"` |
| interaction | `price:weight` | `price:weight` | `c.price#c.weight` | `price:weight` | `price:weight` |
| factor × continuous | `factor(year)2005:x` | `year::2005:x` | `2005.year#c.x` | `C(year)[T.2005]:x` | `2005.year#c.x` |
| omitted (collinear) | `NA` estimate | dropped, in `collin.var` | `o.x` | dropped | row with `dropped: "collinear"` |

### 4.5 `structures` (optional)

Named complex results. Each structure is an object with a `kind`, so a reader can decode it
without knowing the estimator. A name holds one structure or a list of them.

| `kind` | Content |
|---|---|
| `matrix` | `data` (list of rows) with `labels`, or `row_labels` and `col_labels` |
| `table` | `columns` and `rows` |
| `series` | `index` and `values` |
| `tree` | a nested tree (a fitted decision tree, for example) |
| `object` | any nested object |
| `link` | the structure's data is in an attachment (section 8) |

Registered names (profiles define their required shape):

- `vcov`: a list, one per variance-covariance matrix computed (iid, HC1, CRV1, ...). Each
  carries `type`, `cluster`, `n_clusters`, `df_t` (the df used for t tests and confidence
  intervals) and `ssc`, the small-sample correction written out in full: `convention` (the
  tool whose convention it reproduces, e.g. `"fixest"`, `"reghdfe"`), `formula`, `factors`
  and what K counted. The one marked `default: true` is the one `parameters` was computed
  from.

  ```json
  "vcov": [{"kind": "matrix", "labels": ["x1", "x2"], "data": [[...], [...]],
            "type": "CRV1", "cluster": ["pitcher"], "n_clusters": {"pitcher": 1172},
            "ssc": {"formula": "G/(G-1) * (N-1)/(N-K)", "factors": {...}, "K_counts": "...",
                    "convention": "fixest"},
            "df_t": 1171, "default": true}]
  ```

- `fixed_effects`: a list, one `{kind: "object", name, levels, ...}` per fixed effect: levels
  in the sample and in the data, redundant levels and how they were found, nesting (in
  clusters, in other fixed effects). Counts only, never the level values.
- `random_effects`: variance components.
- `numerics`: whether the algorithm is `iterative`, `algorithm`, `tolerance`, `iterations`,
  `converged`, solver, rank, condition number, collinearity settings.
- `hyperparameters`: for machine-learning estimators, with tuning results if any.
- `first_stage`: instrumental-variables diagnostics (see the `iv` profile).

A structure that is spilled to an attachment keeps its non-data fields (a vcov keeps `type`,
`ssc`, `cluster`, `default`) and becomes `{kind: "link", attachment, spilled_kind, ...}`.

### 4.6 `provenance` (expected)

Everything about how and where the run happened. This is where a discrepancy is traced, so
the section is deliberately open-ended: writers fill each part as far as they can, and any
member not defined here is allowed.

- `software`: a list of components, each `{name, version, purl, role, source, hash,
  attributes, lock, container}`.
  - `purl` is a [Package URL], which identifies a component the same way across ecosystems:
    `pkg:cran/fixest@0.14.2`, `pkg:pypi/numpy@2.1.0`, `pkg:github/<owner>/<repo>@<commit>`.
    Software with no purl type (Stata, SPSS) uses `pkg:generic/stata@19.5` plus
    `attributes`.
  - `role`: `estimator`, `language`, `dependency`, `system` (BLAS, OpenMP, MPI) or
    `container`.
  - `source`: CRAN, PyPI, conda, SSC, or a git commit with a dirty flag.
  - `lock`: a pointer to a full lock file or SBOM (`renv.lock`, `pylock.toml`,
    `conda-lock.yml`, CycloneDX), by path and sha256. The record lists only the components
    that matter; the lock file has the rest.
  - `container`: image reference and digest (OCI, Apptainer `.sif` sha256).
- `environment`: operating system, kernel, locale, time zone, and:
  - hardware: CPU model, sockets, cores, threads, instruction-set flags that change
    floating-point results (AVX2, AVX-512, FMA), memory, GPU and driver;
  - numerical libraries: the BLAS/LAPACK in use, its version, threading layer and thread
    count (`threadpools`);
  - random numbers: generator, seed, state (`random`);
  - environment `variables`: an allowlist only (`OMP_NUM_THREADS`, `MKL_NUM_THREADS`, ...).
    Writers MUST NOT dump the full environment, which can carry credentials.
- `execution`: `started`, `finished`, `elapsed_seconds` and `processor_seconds` (a large gap
  between them means waiting or contention), timing by `stages`, `peak_memory_bytes`;
  `invocation` (command line, script path and sha256, working directory, interactive or
  batch); `scheduler`; `workers`; `launch` (launch parameters, resolved); `session` (the
  session id, when the run was part of one).
  - `scheduler` is `{type, ...}` in the scheduler's own field names. For SLURM: `JobID`,
    `JobName`, `Partition`, `Account`, `QOS`, `NodeList`, `AllocCPUS`, `AllocTRES`,
    `ReqMem`, `Submit`, `Start`, `End`, `Elapsed`, `MaxRSS`, `State`, `ExitCode`,
    `SubmitLine`, `WorkDir` (as `sacct --format` spells them). PBS, LSF and SGE use their own
    names under their own `type`.
- `agent`: the user and host.
- `data`: a list of inputs, each `{role, name, version, location, checksum, rows, columns,
  source, license, publication}`.
  - `checksum` is `{algorithm, value, of, method}`. `of` says what was hashed: a `file`, a
    manifest (such as a `MANIFEST.sha256`), or `in-memory` content. For in-memory content the
    format defines no single procedure, so `method` is REQUIRED and names it
    (`stata-datasignature`, `R digest::digest(df, "xxhash64")`,
    `pandas.util.hash_pandas_object`). Two checksums are comparable only when their
    `method`s match.
  - `publication`: where the data is published (the block of section 5).

What each kind of producer can usually fill (a guide for writers, not a requirement):

| Producer | Software | Environment | Execution |
|---|---|---|---|
| base R | `R.version`, attached and loaded packages (`sessionInfo()`), optionally `renv.lock` | `platform`, `running`, BLAS/LAPACK, `La_version()`, locale, `tzone`, `RNGkind()` | `Sys.time()` around the call, `proc.time()`, `commandArgs()` |
| Stata | `c(stata_version)`, `c(version)`, `c(born_date)`, edition, ado versions (`which`), SSC packages | `c(os)`, `c(osdtl)`, `c(machine_type)`, `c(byteorder)`, `c(processors)`, `c(rngtype)`, `c(rngstate)` | `c(current_date)`, `c(current_time)`, `timer`, `c(mode)`, `c(pwd)`, `e(cmdline)` |
| SPSS | version, edition, fix pack, extension bundles | OS, `SHOW` settings (`RNG`, `SEED`, ...) | the Notes table: output created, syntax, input data, filter/weight/split, processor and elapsed time |
| Python | interpreter, packages (`importlib.metadata`), optionally `pylock.toml` or a conda lock | `platform`, `threadpoolctl`, `os.cpu_count()`, allowlisted variables | `time`, `resource.getrusage`, `sys.argv` |

### 4.7 Identifying details

Some provenance fields identify people or places: the user, hosts, paths, job ids, accounts,
command lines, working directories, data locations. They help trace a discrepancy, so writers
SHOULD include them by default, but the format never requires them, and they MUST be easy to
remove:

- **The schemas mark them**: each identifying field carries `"x-identifying": true`. An
  extension's or profile's schema marks its own the same way. A redactor needs only the
  schemas, not knowledge of each tool.
- **Redaction** removes each marked value or replaces it with `hmac-sha256:<hex>`, an
  HMAC-SHA256 of the value's canonical JSON (RFC 8785) under a secret salt, so that records
  redacted with the same salt still compare equal.
- Content hashes (data checksums, a script's sha256) identify content, not people, and are
  kept.
- Redaction MUST NOT change the sections covered by the core digest (7.2).
- The redactor appends a `history` entry with `action: "redacted"`, the `method` (`removed`
  or `hmac-sha256`), the `fields` changed and, when hashing, a `salt_id` (a short hash that
  names the salt without revealing it), so a reader knows what is missing and which records
  are comparable.

## 5. `publication` (optional)

Where the result appears, so that a number in a paper can be traced to the record that
produced it, and the record back to the paper and its materials. The same block describes
published reference values (6) and published data (`provenance.data[*].publication`).

```json
"publication": {
  "citation": {"id": "parsons2011", "type": "article-journal",
               "title": "Strike Three: Discrimination, Incentives, and Evaluation",
               "author": [{"family": "Parsons", "given": "Christopher A."},
                          {"family": "Sulaeman", "given": "Johan"},
                          {"family": "Yates", "given": "Michael C."},
                          {"family": "Hamermesh", "given": "Daniel S."}],
               "issued": {"date-parts": [[2011]]}, "container-title": "American Economic Review",
               "volume": "101", "issue": "4", "page": "1410-1435",
               "DOI": "10.1257/aer.101.4.1410"},
  "locator": {"study": "1", "table": "3", "panel": "A", "column": "9", "row": null,
              "label": "Table 3, column 9"},
  "status": "published",
  "ascollected_url": "https://ascollected.org/ZJ6_Z47",
  "researchbox_url": "https://researchbox.org/15",
  "researchbox_files": [7, 12],
  "aspredicted_url": null,
  "replication_package": {"doi": "10.3886/E112434V1", "url": "https://www.openicpsr.org/openicpsr/project/112434"},
  "links": [{"rel": "preregistration", "url": "..."}, {"rel": "osf", "url": "..."}]
}
```

(The AsCollected and ResearchBox URLs are public examples that belong to other papers; they
only illustrate the fields.)

- `citation` is [CSL-JSON], the citation format of Zotero, pandoc, Mendeley and CrossRef, so
  it can be pasted from a reference manager or fetched from a DOI. `type` is required; CSL's
  own `id` is not. Name objects use only CSL's keys (`family`, `given`, `literal`, ...).
  Working papers and preprints use `type: "report"` or `"article"` with `number` and
  `publisher`.
- `locator` says where in the work: `study`, `table`, `panel`, `column`, `row`, `figure`,
  `equation`, `page`, `appendix`, `section`, any of which can be absent, **plus** `label`,
  the location as printed (`"Table A4, col. (3)"`). A result that appears more than once
  uses `locators` (a list) instead; a record MUST NOT have both.
- `status`: `published`, `accepted`, `submitted`, `working-paper`, `preprint` or
  `unpublished`. `citation.version` says which version of the paper the locator refers to,
  since table numbers move between drafts.
- Named links for services the format wants to encourage: `ascollected_url`,
  `researchbox_url` (with `researchbox_files`, file ids in the box), `aspredicted_url`, and
  `replication_package` (`{doi, url}`: openICPSR, Dataverse, Zenodo). Each SHOULD point to the
  specific version cited.
- `links`: anything else, as `{rel, url}`.

## 6. `validation` (optional)

Most records have no `validation`. It is for when the estimator itself is in question: a
custom or untested estimator, a new release, a replication. It has two parts.

**`equivalents`**: the same model elsewhere, each in a `style`:

| `style` | Content |
|---|---|
| `code` | `{software, language, code}`, e.g. `reghdfe y x, absorb(fe) vce(cluster c)` |
| `description` | prose: how the reference was produced |
| `record` | another `estimation` record, by path, sha256 and id, or embedded whole |
| `published` | `{publication, values}`: numbers from a paper, with a `publication` block (5) |

The list of styles is open: a writer MAY use a new style (`notebook`, `container`, ...), and
readers MUST skip styles they don't know. An equivalent can be listed without a comparison
(the code to run, not yet run).

**`comparisons`**: what was compared against which equivalent, and how close it came:

```json
"comparisons": [
  {"reference": "pyfixest", "quantities": ["estimate", "std_error", "nobs"],
   "term_map": {"x::2": "x[T.2]"}, "tolerance": {"rel": 1e-6},
   "max_abs_diff": {...}, "max_rel_diff": {...}, "pass": true,
   "details": [{"term": "x1", "quantity": "estimate", "value": ..., "reference": ...,
                "diff": ...}]}],
"verdict": "pass"
```

## 7. Extensions, history and integrity

### 7.1 `extensions` and `history`

Any tool that handles a record MAY add a block under `extensions`, in its own namespace: the
estimator (with its own diagnostic detail), or a tool later in a chain (a table exporter, a
replication harness, a cluster accounting tool).

```json
"extensions": {
  "dfeols":   {"schema": "dfeols/0.1", "by": {"name": "dfeols", "version": "0.8.0"},
               "added": "2026-10-24T15:02:11Z", ...},
  "harness":  {"schema": "dfeols-harness/0.1", "by": {...}, "added": "...",
               "reference_file": "reference.json", ...}
}
```

- A block SHOULD carry `schema` (the schema that validates it), `by` (`{name, version}`)
  and `added`.
- A namespace belongs to the tool that writes it. A tool MUST add or replace only its own
  block, never another tool's block or a core section.
- A tool that changes results (a new vcov, a new sample) MUST write a **new record** with
  `meta.parent` set, not a block.
- Each tool that creates, extends, redacts or validates a record SHOULD append to `history`
  an entry `{when, by: {name, version}, action, sections}`, where `action` is `created`,
  `extended`, `redacted` or `validated`. The chain of tools that touched a record is then
  explicit and in order.
- The core validator ignores the content of blocks. Readers MUST skip blocks they don't
  know.

### 7.2 Core digest

`meta.core_digest` lets anyone check whether the results were edited after the run, as
opposed to only annotated:

```text
"core_digest": {"algorithm": "sha256", "canonicalization": "RFC8785", "value": "<hex>"}
```

- `value` is the SHA-256 of the [RFC 8785] (JSON Canonicalization Scheme) serialization of an
  object holding the record's `meta` (without `core_digest`), `specification`, `metrics`,
  `parameters` and `structures`, each only if present, as written (non-finite numbers as
  strings, spilled structures as links).
- The digest is OPTIONAL. Writers SHOULD compute it by default and MAY let users turn it off.
- Validators report a missing digest as information and a digest that doesn't match as a
  warning.

## 8. Attachments and size

### 8.1 `attachments` (optional)

Large outputs (fixed-effect coefficients, residuals, fitted values, a vcov with thousands of
terms, predictions) live in side files. The record holds only a link:

```json
{"id": "fe_coefs", "role": "fe_coefficients", "path": "fe_coefs.parquet",
 "media_type": "application/vnd.apache.parquet", "created": "2026-10-24T15:02:11Z",
 "sha256": "...", "bytes": 81234567, "rows": 1838676, "columns": ["fe", "level", "estimate"]}
```

- `id` and `path` are required; `id`s are unique within a record. `sha256` is expected.
- `path` is relative to the record's folder, or a URI. A record stays valid when the file is
  missing; the hash says whether a file found later is the right one.
- A structure points to an attachment with `{kind: "link", attachment: "<id>"}`.
- Parquet is RECOMMENDED for tables. Per-observation and per-level output MUST be an
  attachment, and writers SHOULD write such attachments only when asked.

### 8.2 Size limits

| Limit | Validator |
|---|---|
| record above 1 MB (10^6 bytes) | warning, naming the largest section |
| one array above 10,000 elements | warning, naming the array |
| record above 16 MB | error |

An array's elements are its items, with nested arrays counted by their leaves (a 100 × 100
matrix has 10,000). Writers SHOULD move a structure above these limits into an attachment
automatically, leaving a `link`, so the easy path is the small one.

## 9. Profiles

### 9.1 What a profile is

A profile is a named, versioned set of rules on top of the core: which `metrics`,
`parameters` columns and `structures` a record of that kind must have, and their shapes. A
record lists the profiles it follows in `meta.profiles`, and a validator checks the core plus
each claimed profile. Profiles give model-specific requirements without a new format per
model.

A profile is a JSON Schema (draft 2020-12) whose `title` is its name (`linear-fe/0.1`) and
whose `$defs/rules` holds its own rules. The file as a whole is `allOf` the core and its
rules, so it validates a complete record.

**Standard profiles** describe a kind of model shared across tools. Each is built from the
most popular tools for that task in Stata, R and Python:

- **Vocabulary = the union**: every quantity any surveyed tool saves gets one name, a
  definition and a mapping to each tool's own name (`x-tools` in the schema).
- **Requirements = what (nearly) all of them save by default.** A quantity most tools
  compute only on request is not required; it MAY be *expected* (validators warn when it is
  missing).
- **Options = the union**, with each tool's default, so a reader can see which option in
  another tool corresponds, which explains most discrepancies between tools.

**Tool profiles** describe one program's records (`dfeols/0.1`). A tool profile builds on
standard ones and MAY depart from them where the tool must, but MUST declare it:

- `x-extends` lists the profiles it builds on (`["linear-fe/0.1"]`).
- `x-deviations` lists each departure as `{path, reason}`, where `path` uses the syntax of
  section 1.1 and covers its sub-paths.
- A profile whose `$defs/rules` includes its base's rules has no departures. Standard profiles
  don't deviate from each other.

### 9.2 What a validator reports

- Errors against the core or a claimed profile make the record invalid.
- For a claimed profile that extends a base the record doesn't also claim, the validator
  checks the record against the base and reports: information when the record meets it ("also
  meets linear-fe/0.1"); information for each failure the profile declares in
  `x-deviations`; a **warning** for each failure it doesn't declare. The record stays valid
  either way: it is judged by the profiles it claims.
- A claimed profile the validator doesn't know is reported as information.

### 9.3 The catalog

[`schema/catalog.json`](../schema/catalog.json) lists the core schema and every registered
profile: `name`, `file`, `kind` (`standard` or `tool`), `status` (`draft` or `published`),
`maintainer`, `description` and `examples`. Profiles are added by pull request
([CONTRIBUTING.md](../CONTRIBUTING.md)); CI checks each one.

- **Published versions never change.** A published entry carries the sha256 of its file, and
  a fix is a new version (`/0.2`).
- **Local drafts**: validators SHOULD accept extra profile folders (the reference validator
  reads `$ESTIMATION_SCHEMA_PATH`), so a profile can be tried before its pull request. A
  local profile MUST NOT replace a catalog name.
- **License**: everything in the catalog is dedicated to the public domain under [CC0 1.0],
  so any tool can copy, embed or adapt a profile under its own license. Contributed profiles
  MUST be CC0 too, and carry `"x-license": "CC0-1.0"`.

### 9.4 Registered profiles (0.1)

| Profile | Kind | Requires |
|---|---|---|
| [`inference/0.1`](profiles/inference.md) | standard | `parameters` with `estimate`, `std_error`, `p_value`; a default `vcov` with `type` and `ssc.convention`; `metrics.nobs` and `df_residual` |
| [`linear-fe/0.1`](profiles/linear-fe.md) | standard | `inference` plus `n_singletons`, `specification.options.drop_singletons`, and `structures.fixed_effects` with `levels` |
| [`iv/0.1`](profiles/iv.md) | standard | `inference` plus `specification.endogenous` and `instruments`; `structures.first_stage` expected |
| [`dfeols/0.1`](profiles/dfeols.md) | tool | `linear-fe` plus `extensions.dfeols`: the first worked tool profile |
| [`did/0.1`](profiles/did.md) | standard | `meta.estimator.method`; `specification.did` (time, comparison, cohort or treatment); `metrics.nobs`; `estimate` and `std_error`; a `did` object saying which effect a row is; a default `vcov` with `type`; `structures.did` expected |
| [`did2s/0.1`](profiles/did2s.md) | tool | `did` plus first- and second-stage specifications, the cluster, and a two-stage GMM or bootstrap vcov |
| [`csdid/0.1`](profiles/csdid.md) | tool | `did` plus `method`, `agg`, `typebase`, an influence-function or wild-bootstrap vcov, and the `e(gtt)` cells |
| [`glm/0.1`](profiles/glm.md) | standard | `meta.estimator.distribution` and `link`; `estimate`, `std_error`, `p_value`; `metrics.nobs`; a default `vcov` with `type` and `ssc.convention`; `structures.numerics.converged`; `log_lik` and `deviance` expected |
| [`ppmlhdfe/0.1`](profiles/ppmlhdfe.md) | tool | `glm` (Poisson, log) plus separation and singleton counts and options, and `structures.fixed_effects` |
| [`conditional-logit/0.1`](profiles/conditional-logit.md) | standard | `specification.groups`; `options.likelihood` and `drop_uninformative`; `estimate`, `std_error`, `p_value`; `metrics.nobs`; a default `vcov` with `type` and `ssc.convention`; `n_groups`, `log_lik`, `structures.groups` expected |
| [`mixed/0.1`](profiles/mixed.md) | standard | `meta.estimator.method` (REML/ML/quadrature); `specification.random_effects`; fixed-effect `estimate` and `std_error`; a `vc` object on variance-component rows; `metrics.nobs`; `structures.random_effects` with `levels`; a default `vcov` with `type`; `numerics.converged`; `log_lik` and `singular` expected |

Planned as needed: `glm` (deviance, log-likelihood, family and link), `mixed` (variance
components), `ml` (scikit-learn, tidymodels, xgboost).

## 10. Schema locations and versions

- The format version is `schema` in each record: `"estimation/0.1"` during the draft, then
  `"estimation/1"`.
- Schemas are published at
  `https://estimation-format.github.io/estimation/schema/<file>`, which is also each file's
  `$id` (for example `.../schema/estimation-0.1.json`, `.../schema/profiles/linear-fe-0.1.json`).
  Profiles refer to the core by relative `$ref`, so a local copy validates offline. These
  locations may change before the first published version; a published `$id` never changes.
- Validators SHOULD NOT fetch schemas over the network; the reference validator ships them.

## 11. Collections (planned, not yet specified)

A planned `estimation-collection` will group records: a paper's results ordered by locator
(`members`), or the timeline of a session or replication (`events`), with the session's own
provenance. A collection will be an export built from records; each member stays a
self-contained record. Comments on this plan are welcome.

## 12. Example: base R `lm`, minimal

```json
{"schema": "estimation/0.1",
 "meta": {"id": "6f1c...", "created": "2026-10-24T15:02:11Z", "status": "ok",
          "estimator": {"family": "linear", "method": "ols"}, "responses": ["mpg"],
          "profiles": ["inference/0.1"]},
 "specification": {"call": "lm(mpg ~ wt, data = mtcars)",
                   "formula": {"text": "mpg ~ wt", "syntax": "R"}},
 "metrics": {"nobs": 32, "df_residual": 30, "r2": 0.7528, "sigma": 3.046, "conf_level": 0.95},
 "parameters": [
   {"term": "(Intercept)", "estimate": 37.285, "std_error": 1.8776, "statistic": 19.858,
    "p_value": 8.24e-19},
   {"term": "wt", "estimate": -5.3445, "std_error": 0.5591, "statistic": -9.559,
    "p_value": 1.29e-10}],
 "structures": {"vcov": [{"kind": "matrix", "labels": ["(Intercept)", "wt"],
                          "data": [[3.525, -1.0], [-1.0, 0.3126]], "type": "iid",
                          "ssc": {"convention": "R lm", "formula": "sigma^2 with N - K"},
                          "df_t": 30, "default": true}]},
 "provenance": {"software": [{"name": "R", "version": "4.5.1", "role": "language"},
                             {"name": "stats", "version": "4.5.1", "role": "estimator"}],
                "environment": {"os": "Ubuntu 24.04", "blas": "OpenBLAS 0.3.26"}}}
```

(Numbers illustrative.) [`schema/examples/`](../schema/examples/) has complete records,
including a linear fixed-effects record with every expected section filled.

## Appendix A. Related formats

No existing format covers one estimation run across software. The nearest pieces, and what
this format borrows from them:

| Existing | Covers | Missing | Borrowed |
|---|---|---|---|
| broom `tidy`/`glance` (R) | parameter and fit-statistic names; read by modelsummary | a file format; vcov, provenance | parameter and metric names |
| PMML | scoring a fitted model in another system | inference, provenance | |
| Stata `e()`, `estimates save`, `collect` | full detail of one run in Stata | readable outside Stata | `c()` as a checklist of environment |
| SPSS OMS and the Notes table | output tables as XML; the run's filter, weight, split, syntax, timing | describes display tables, not a model | `specification.state`, processor vs elapsed time |
| fixest, pyfixest, linearmodels result objects | full detail, one tool | in memory, tool-specific | the profile vocabularies |
| MLflow runs | parameters, metrics, artifacts by link, source commit | inference, data identity | links, tags |
| renv.lock, pylock.toml, conda lock, SBOMs | exact package sets with hashes | the model | `provenance.software[*].lock` |
| Package URL (purl) | one identifier for software across ecosystems | | `provenance.software[*].purl` |
| W3C PROV, RO-Crate Process Run Crate | a run as an activity with inputs, outputs, agent | anything statistical | the shape of `provenance` |
| SLURM `sacct` | job, allocation, timing, memory | | `provenance.execution.scheduler` field names |
| CSL-JSON | citations | | `publication.citation` |
| AsCollected, ResearchBox, AsPredicted | provenance of a paper's data, code and pre-registration | the results | named links in `publication` |

## References

- [RFC 2119]: Key words for use in RFCs to Indicate Requirement Levels.
- [RFC 8174]: Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words.
- [RFC 8259]: The JavaScript Object Notation (JSON) Data Interchange Format.
- [RFC 3339]: Date and Time on the Internet: Timestamps.
- [RFC 8785]: JSON Canonicalization Scheme (JCS).
- [RFC 9562]: Universally Unique IDentifiers (UUIDs).
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12).
- [Package URL]: purl specification.
- [CSL-JSON]: Citation Style Language data schema.
- [CC0 1.0]: Creative Commons CC0 1.0 Universal.

[RFC 2119]: https://www.rfc-editor.org/rfc/rfc2119
[RFC 8174]: https://www.rfc-editor.org/rfc/rfc8174
[RFC 8259]: https://www.rfc-editor.org/rfc/rfc8259
[RFC 3339]: https://www.rfc-editor.org/rfc/rfc3339
[RFC 8785]: https://www.rfc-editor.org/rfc/rfc8785
[RFC 9562]: https://www.rfc-editor.org/rfc/rfc9562
[Package URL]: https://github.com/package-url/purl-spec
[CSL-JSON]: https://github.com/citation-style-language/schema
[CC0 1.0]: https://creativecommons.org/publicdomain/zero/1.0/

# Proposal: disclosure levels and purpose profiles

Status: **draft for review**. Ted's answers so far (2026-11-05) are folded in; the open
questions are at the end.

## Problem

A writer today records as much as it can: the spec says writers SHOULD fill every expected
member and SHOULD include identifying details by default (4.7), and estrec lists every loaded
namespace in `provenance.software`. That suits a replication harness, but it puts people off
who only want to send someone a coefficient and its standard error, or who are wary of
surveillance or information leakage. The amount a record discloses should be the sharer's
choice, and a small record should be a first-class record, not a degraded one.

The opposite need exists too: some destinations (a journal, a data editor, a registry) need a
certain amount of detail, and a writer should be able to produce exactly that and a validator
should be able to check it.

These are two separate axes:

- a **disclosure level** is a *ceiling*: the most the sharer is willing to reveal;
- a **purpose profile** is a *floor*: the least a destination needs.

A writer takes both. If a purpose needs something the level forbids, the writer stops and
names the field; it never discloses more than asked, or silently produces a record that falls
short of the purpose.

(Not "profile" for the levels: that word already means the validation profiles in
`meta.profiles`, section 9.)

## 1. Disclosure levels

Each level includes everything in the levels below it.

| Level | Adds |
|---|---|
| 1 | `parameters` rows with `term`, `estimate`, `std_error`, `p_value`, `conf_low`, `conf_high` and the df they use; `metrics.nobs` and `conf_level` |
| 2 | the model's diagnostic and summary measures: the other `metrics` (R², log-likelihood, AIC, ...), the default vcov's `type` and `ssc`, `tests`, `messages` |
| 3 | `specification` (formula, terms, fixed effects, clusters, weights, options, sample and drop counts) and structure counts (FE levels, number of clusters), the other vcovs |
| 4 | `provenance.software` (see 1.2), `provenance.data` names, versions and checksums, `structures.numerics`, tool `extensions` |
| 5 | `provenance.environment` (hardware, BLAS, threads, locale), `execution` (timing, scheduler, invocation), `agent`, data `location` |

**The default is 4** (Ted). Most identifying fields (4.7) are at level 5, so a default record
carries almost none of them. Identifying fields keep their own switch on top of the level:
level 5 makes them *allowed*, `redact` / `identifying = FALSE` still removes or hashes them.
Attachments stay opt-in at every level (8.1).

### 1.1 What every level still carries

The core requires `schema`, `meta.id`, `meta.created`, `meta.status` and `parameters`. At
level 1:

- `meta.id` is a random UUID and reveals nothing.
- `meta.created` MAY be a date instead of a timestamp.
- The `history` entry is only `{action: "created", level: 1}`, without the writer's name and
  version.
- `meta.estimator`, `responses`, `title` and `producer` are left out unless the user passes
  them.

### 1.2 The software list

Listing every loaded package is too much for a default (Ted). At level 4 `software` holds the
estimator, the language and the writer, plus the estimator's own direct dependencies that can
change results (each writer lists these for its estimator; not yet worked out). The full
list of loaded packages is level 5, or a `lock` pointer (path and sha256) that commits to the
environment without listing it.

### 1.3 The record says its level

`meta.disclosure: {level: 1}` (inside the digest, so it can't be quietly changed). A reader
then knows that a missing member was withheld, not unknown.

- Validators MUST NOT warn about an expected member the declared level excludes; they report
  it as information.
- A record MUST NOT contain fields above its declared level; a validator reports that as an
  error.
- A writer MUST NOT claim a model profile the level makes impossible (`linear-fe/0.1` needs
  `structures.fixed_effects` at level 3). It leaves the claim out of `meta.profiles` and says
  so in `meta.messages`.

### 1.4 The schemas mark the levels

Like `x-identifying` (4.7), each field in the core and in each profile carries
`"x-level": n`. Then:

- the ladder is machine-readable and one table, not a rule in every writer;
- a validator can check 1.3 from the schemas alone;
- one tool can **lower** a record's level (write a level-1 record from a full one) the way the
  redactor removes identifying fields, without knowing the estimator. Lowering changes
  sections inside the core digest, so the lowered record gets a new `meta.id` with `meta.parent`
  set to the original, a new digest and a `history` entry with `action: "reduced"`.

## 2. Purpose profiles

A third `kind` of profile in the catalog, next to `standard` and `tool`: `purpose`. A purpose
profile says what a destination needs (`publication/0.1`, a journal's or data editor's own), as
a JSON Schema with `$defs/rules` like any profile, plus `x-min-level`: the lowest disclosure
level that can meet it.

What this means in practice:

- **It reuses the existing machinery.** A record claims `["linear-fe/0.1",
  "publication/0.1"]` and the validator checks both; a purpose profile only adds
  requirements, so it composes with any model profile. Local drafts work through
  `$ESTIMATION_SCHEMA_PATH`, so a journal can try one before registering it.
- **The writer can aim at it.** `to_estimation(fit, purpose = "publication/0.1")` picks the
  level `x-min-level` gives (unless the user set one) and fails early, naming the field, if
  the level is too low or the fit lacks something the purpose needs.
- **It is a floor, not a ceiling.** A purpose profile cannot forbid content; the sharer's level
  does that.
- **Governance.** Catalog profiles must be CC0 (9.3). A journal that won't license its rules
  that way can still publish a local profile, but it can't be in the catalog.
- **The risk** is that purpose profiles become de-facto mandates to disclose more. They should
  name what the destination really needs and no more; review in CONTRIBUTING.md should ask for
  the destination's own stated requirement for each rule.
- **Content first.** Before writing any purpose profile, collect what the destination actually
  asks for (journal and data-editor policies), not what we guess.

## 3. Later, not now: predictions

A way to check whether a record tests what a preregistration predicted (AsPredicted and similar)
fits this ecosystem but isn't part of the format change: it would compare a results record
with a separate prediction document. `parameters` stays required in the core. (Ted,
2026-11-05.)

## 4. Writers

| Writer | Change |
|---|---|
| Python `prepare()` | `level=` (default 4) and `purpose=`; drop fields above the level using `x-level`; trim the software list |
| `estimation_format` | `reduce(record, level)`, as `redact` |
| estrec | `level =` and `purpose =` on `to_estimation()`; `call =` becomes "keep `specification.call` at level 3+"; trim `.est_software()` at level 4 |
| dfeols | same; the OSCER harness asks for level 5 explicitly, since it needs scheduler and timing |
| converters (pyfixest, fixest, reghdfe) | `level=` only |

## Questions for Ted

1. **Purpose profiles in the catalog** (section 2): go ahead, given the implications above?
   Or keep only the levels for now and add `kind: "purpose"` when there's a first real
   destination to write one for?
2. **Lowering** (1.4): a lowered record is a new record with `meta.parent` (recommended),
   or the same `meta.id` with a recomputed digest?
3. **Level 4 software** (1.2): estimator, language, writer and the estimator's result-relevant
   dependencies. Is "result-relevant" right, or only the first three?
4. **Version**: amend 0.1 (still a draft), as for `tests`?

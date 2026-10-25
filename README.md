# estimation

**A file format for one statistical estimation run**: what was estimated, what came out, and
how and where it ran, as a small JSON record that any software can write and read.

> **Status: 0.1 draft for comment.** The format may still change. Please open an issue with
> anything that would stop your tool from writing or reading these records.

Why: results from two tools, or two runs, often differ, and finding out why usually means
rerunning both. An `estimation` record keeps what you need to explain the difference: the
resolved options, the sample and singleton counts, the small-sample correction behind the
standard errors, convergence, the software and environment, and the data's checksum.

- **Any software, any model**: a small core every tool can fill (`meta`, `parameters`,
  `metrics`, `specification`, `provenance`), with **profiles** for the rules of a kind of
  model (`inference`, `linear-fe`, `iv`, `did`, `glm`, `conditional-logit`, `mixed`) or one tool.
- **Small**: results and metadata only; residuals, fitted values and fixed-effect
  coefficients go in linked attachments.
- **Traceable**: records can cite the paper and table they appear in, carry an integrity
  digest, and be redacted of user and host details before sharing.

## Contents

| Path | What | License |
|---|---|---|
| [`spec/estimation.md`](spec/estimation.md) | the specification | CC0 1.0 |
| [`spec/profiles/`](spec/profiles/) | the profiles, with field mappings across Stata, R, Python and Julia tools | CC0 1.0 |
| [`schema/`](schema/) | JSON Schemas (2020-12) for the core and the profiles, the catalog, example records | CC0 1.0 |
| [`src/estimation_format/`](src/estimation_format/) | `estimation-format`, the reference validator, writer and redactor (Python) | MIT |

Schemas are served at `https://estimation-format.github.io/estimation/schema/`.

## A minimal record

```json
{"schema": "estimation/0.1",
 "meta": {"id": "6f1c0000-0000-4000-8000-000000000001", "created": "2026-10-24T15:02:11Z",
          "status": "ok", "estimator": {"family": "linear", "method": "ols"},
          "responses": ["mpg"], "profiles": ["inference/0.1"]},
 "metrics": {"nobs": 32, "df_residual": 30, "r2": 0.7528},
 "parameters": [
   {"term": "(Intercept)", "estimate": 37.285, "std_error": 1.8776, "p_value": 8.24e-19},
   {"term": "wt", "estimate": -5.3445, "std_error": 0.5591, "p_value": 1.29e-10}],
 "structures": {"vcov": [{"kind": "matrix", "labels": ["(Intercept)", "wt"],
                          "data": [[3.525, -1.0], [-1.0, 0.3126]], "type": "iid",
                          "ssc": {"convention": "R lm"}, "default": true}]}}
```

## The validator

```bash
pip install 'estimation-format[jsonschema]'      # not yet on PyPI; for now: pip install .
estimation validate model.estimation.json
estimation redact model.estimation.json -o shareable.estimation.json
estimation digest model.estimation.json
```

```python
import estimation_format as ef

rec = ef.new_record(
    rows,
    estimator={"family": "linear", "method": "ols"},
    profiles=["inference/0.1"],
    metrics={"nobs": 32, "df_residual": 30},
)
ef.write(rec, "model.estimation.json")  # spills large structures, adds the digest
for issue in ef.validate(ef.read("model.estimation.json")):
    print(issue)
```

It needs only the standard library; `jsonschema` adds full schema validation and `pyarrow`
writes large structures as Parquet attachments.

## Contributing

Profiles for new model types or tools come by pull request; see
[CONTRIBUTING.md](CONTRIBUTING.md). Writers for your own tool don't need anyone's permission:
the schemas are public domain.

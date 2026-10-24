# Contributing

Comments on the 0.1 draft are the most useful contribution right now: open an issue with
what your tool can or can't fill, names that clash with your tool's, or rules that look
wrong.

## Licenses

- The specification (`spec/`), schemas, catalog and example records (`schema/`) are
  dedicated to the public domain under CC0 1.0 (`schema/LICENSE`). Contributions to them
  must be too.
- The Python package (`src/`, `tests/`) is MIT (`LICENSE`).

## Adding a profile

A *profile* adds rules for one kind of model (`linear-fe/0.1`, `iv/0.1`) or one tool's
records (`dfeols/0.1`). To add one, open a pull request with:

- `schema/profiles/<name>-<version>.json`: a JSON Schema (draft 2020-12) whose `title` is the
  profile name (`reghdfe/0.1`) and whose `$id` is
  `https://estimation-format.github.io/estimation/schema/profiles/<file>`. Its rules go in
  `$defs/rules`, and the file is `allOf: [core, #/$defs/rules]`, like the existing profiles.
- At least one example record in `schema/examples/` that claims the profile.
- `"x-license": "CC0-1.0"` in the profile file.
- An entry in `schema/catalog.json`: `name`, `file`, `kind` (`tool` for one program's
  records, `standard` for a model type shared across tools), `status: "draft"`, `maintainer`
  (your GitHub handle), `description`, `examples`.
- A page in `spec/profiles/` describing it, with the tool's own names for each field.

Tool profiles are encouraged to stay close to a standard one:

- Name the profiles you build on in `x-extends` (e.g. `["linear-fe/0.1"]`). The validator
  checks records against them too, and reports "also meets linear-fe/0.1" when they do.
- Including the base's rules (`allOf: [{"$ref": "linear-fe-0.1.json#/$defs/rules"}]`) keeps
  your records fully conforming, which is the simplest choice.
- Where your tool can't or won't follow the base, list each departure in `x-deviations` as
  `{"path": "metrics.n_singletons", "reason": "..."}`. Declared departures are reported as
  information; undeclared ones as warnings.

`pytest tests/test_catalog.py tests/test_schema.py` runs the checks CI applies: the schema is
valid, names and files match, examples validate, every departure from a base is declared, and
published files are unchanged. A published version never changes; a fix is a new version
(`/0.2`). To try a profile before submitting it, put it in a folder and point
`ESTIMATION_SCHEMA_PATH` (or `estimation validate --schema-path DIR`) at it; a local profile
can't replace one in the catalog.

## Changing the core or a standard profile

Open an issue first. Standard profiles are built from what the popular Stata, R and Python
tools for a task save: the vocabulary is the union, the requirements are what (nearly) all of
them store by default. A proposal is easiest to judge with that survey attached.

## Development

```bash
pip install -e '.[test]'
pytest
```

The spec's JSON examples are tested: `tests/test_schema.py` validates every ```json block in
`spec/estimation.md`, so keep them valid.

# Proposal: a table spec (`estimation-table/0.1`)

Status: **adopted** (Ted, 2026-11-05): recommendations 1-5 as below. On 1, Ted is wary of
growing the format with something outside a record's scope, so the table spec has its own
spec page (`spec/table.md`) and schema, versioned on its own like collections; records, the
record schema and `spec/estimation.md` don't change. Rounding: **no cross-renderer digit
rule** (Ted: presentation, not estimation); each renderer rounds by its own convention.
Ted agreed the idea on 2026-11-05: the browser viewer saves a table as a small "recipe" file
that R and Python can render again.

## What it is

A table spec says **how to lay out a regression table from records**: which records are the
columns, which terms are the rows and what they are called, which statistics go underneath,
and how numbers are shown. It holds **no results**. The numbers always come from the records,
so a table can't drift from the results it shows, and a re-run that writes new records gives
a new table from the same spec.

```json
{"schema": "estimation-table/0.1",
 "meta": {"id": "...", "created": "2026-11-05T09:00:00Z", "title": "Table 2"},
 "sources": [{"id": "src1", "path": "table2.estimation-collection.json"}],
 "columns": [
   {"record": "2b7e6e56-...", "source": "src1", "header": "(1)"},
   {"record": "380a95f5-...", "source": "src1", "header": "(2)", "vcov": "iid"}],
 "rows": [
   {"term": "price_log", "label": "log(price)"},
   {"term": "hhi", "label": "HHI"}],
 "drop": ["^year::"],
 "uncertainty": "std_error",
 "stars": [0.1, 0.05, 0.01],
 "stats": [
   {"metric": "nobs", "label": "N"},
   {"metric": "r2_within", "label": "Within R²", "digits": 3},
   {"vcov_type": true, "label": "Clustered by"},
   {"fixed_effect": "carrier", "label": "Carrier FE"},
   {"label": "Controls", "values": ["No", "Yes"]}],
 "format": {"digits": 3, "thousands": ",", "missing": ""},
 "notes": ["Standard errors clustered by route in parentheses."]}
```

## Recommendations

1. **A document type of the format, beside collections.** It gets its own schema
   (`schema/estimation-table-0.1.json`), a spec section, and validation in the reference
   tools (unknown records, terms that no column has, metrics that no record has). A file that
   only one tool reads would be simpler, but three renderers (browser, R, Python) have to
   agree on it. A schema is how they agree, and it lets other tools (a Stata `esttab`
   bridge, say) read it later. It's **not** part of a record or a collection: those describe
   results, and a table is a view of them. Adopted, kept apart: its own spec page and schema.

2. **Columns name records by `meta.id`, with a path as a hint.** The id stays valid when
   files are moved or renamed. `sources` gives the paths to look in first: record files,
   folders or collections, relative to the spec. A column MAY add `sha256` (the record's
   RFC 8785 hash, as collection members have) to pin the exact version. A renderer then
   warns when the record has changed since the table was made, for example because a test
   was added. A column can also pick its `vcov` (as `tidy(vcov =)` does), a `component` or
   a `response`.

3. **Rows: an ordered list, plus `keep`/`drop` patterns.** `rows` gives order and labels;
   terms not listed follow in record order unless `keep_unlisted: false`. `keep`/`drop` are
   regexes on `term`, as in fixest's `etable` and modelsummary's `coef_omit`. Several terms
   can share one row (`{"terms": ["x", "fit_x"], "label": "x"}`), for OLS vs IV columns, as
   modelsummary's `coef_map` does when two names map to one label. `panels` (Panel A / B) are left for 0.2.

4. **Statistics rows are typed:** a metric (`metric`, the record's name such as `nobs`,
   `r2_within`); the vcov (`vcov_type`, or `n_clusters`); a fixed effect (`fixed_effect`,
   giving "Yes" or "X" when the record has it); a test (`test`, by label or name, showing
   statistic or p-value); or literal `values`, one per column. Typed rows keep each value
   tied to its record. Literal rows are for what records don't hold ("Controls: Yes").

5. **The renderers use what each language already has.** The browser page renders the spec
   itself (HTML on screen; LaTeX, Markdown, CSV out). R's `estrec::render_table(spec)` turns
   it into a `modelsummary()` call (`coef_map`, `gof_map`, `add_rows`, `stars`, `fmt`), so
   the output formats and themes are modelsummary's. Python's `ef.render_table(spec,
   format=)` writes Markdown, LaTeX and HTML itself (stdlib), and returns a great_tables
   object when great_tables is installed.

## Open details

- **Rounding.** Each renderer rounds by its own convention (JavaScript's `toFixed`, R's
  `format`, Python's `format`), so exact binary ties such as `0.125` can differ in the last
  digit between renderers. Decided: that's presentation, so no shared rule (Ted, 2026-11-05).
- **Stars and uncertainty.** `uncertainty` is one of `std_error`, `statistic`, `p_value`,
  `conf_int`, or `null` (estimates only). `stars: null` means no stars. The thresholds and
  symbols live in the spec, so the note under the table is written from them.
- **Missing values.** A term a column doesn't have is blank (`format.missing`). A record
  that can't be found is an error, not a blank column.
- **Size.** Specs are small; no attachments.

## Not in 0.1

Panels, multiple responses side by side (`shape = term + response ~ model`), plots
(coefficient plots from the same spec), and per-cell formatting.

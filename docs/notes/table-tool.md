# Table tool: state and backlog

Handoff notes from the Record viewer chat (f69fc03f, 2026-11-05/06) for the chat that keeps
improving the table tool. Decisions are Ted's unless marked as a proposal.

## What exists

| Piece | Where | Notes |
|---|---|---|
| Table spec | `spec/table.md`, `schema/estimation-table-0.1.json`, `schema/examples/paper.estimation-table.json` | Own document type, versioned apart from the record format (adopted; `docs/proposals/table-spec.md`). Holds layout only, never numbers |
| Python | `src/estimation_format/views.py` (`tidy`, `glance`, `parameters_table`), `table.py` (`new_table`, `validate_table`, `build_table`, `render`, `render_table`, `to_great_table`), `show.py` | Renderers: text, markdown, latex, html, csv; great_tables optional |
| CLI | `estimation show`, `estimation table`, `estimation validate` (detects table specs) | In `records.py` `main()` |
| R (estrec) | `r/R/read.R` (`read_estimation`, `read_collection`, `tidy`/`glance` methods), `r/R/table.R` (`render_table` through modelsummary) | `S3method(generics::tidy, ...)` registered lazily |
| Viewer | `viewer/index.html`, `viewer/estimation-table.js` (UMD: `window.EstTable` / node), generated `examples.js`, `identifying.js` (`python viewer/make_examples.py`) | Static page; Pages deploys it at `/estimation/viewer/` |
| Tests | `tests/test_table.py`, `test_views.py`, `test_show.py`, `test_viewer.py` (+ `viewer_check.js`, node 24); `r/tests/testthat/test-table.R`, `test-read.R` | JS and Python must build identical tables; R matches cell for cell on the example |

Viewer features: drag-and-drop of files and folders; record detail tab; **New table**,
**+ Table** per record, **Table from these** per file; per-column vcov, component, response;
terms (rename, merge, keep/drop); statistics rows (metric, vcov type, clusters, FE yes/no,
test, literal); lines under each estimate (names or templates such as `[{p_value}]`, p-value
decimals, rounded 0.000 or bounded <0.001); live preview whose column heads summarise on
hover and open the record on click; export LaTeX, Markdown, HTML, CSV, text, **Web page**
(self-contained HTML with the records embedded, identifying fields left out by default) and
the table spec (optionally pinning record versions by sha256).

Decisions so far:

- Presentation, not estimation: renderers need not agree on digits.
  There's no cross-renderer rounding rule.
- `uncertainty` can be a list (one row per line); `format.p_digits` sets p-value decimals;
  `format.p_style` is `fixed` or `less_than`.
- Web export redacts the union of the schemas' `x-identifying` paths outside the digest
  sections (meta, specification, metrics, parameters, structures).

## How to work on it

- Keep JS and Python in step. Any change to building or rendering goes in both
  `table.py` and `estimation-table.js`. `tests/test_viewer.py` compares them in node.
- After a schema or example change, run `python viewer/make_examples.py`. A test fails if
  the generated files are stale.
- valiant has no browser. The UI was checked with a node DOM stand-in, so Ted reviews it via
  a private artifact preview (latest: https://claude.ai/artifact/FZJU8TRYRWEFpY64nnyy1Z,
  v4; web-export example https://claude.ai/artifact/LmYbDiLtDB59NqohaPR3LN). Downloads
  don't work inside artifacts; they do on a normal host.
- R: `R CMD check` must stay clean. Use ASCII only in R code (`²` escapes). Ted
  installs packages.
- The Disclosure levels chat (05fe2fb6) also edits this repo, so commit only your own
  files.

## Backlog (proposals; ask Ted before changing behaviour)

1. **Star cuts.** `estimation show` uses modelsummary's cuts (+ .1, * .05, ** .01,
   *** .001). Table specs default to * .1, ** .05, *** .01. Should they be made the same?
   This is still an open question.
2. **Web-page export outside the viewer.** Add `render(..., "webpage")` in Python and
   `render_table(output = "webpage")` in estrec, reusing the viewer's template.
3. **Ted's first review in a real browser** once Pages serves the viewer. Collect his
   rough edges.
4. Possible additions:
   - several panels (Panel A/B) or column groups ("spanners") in the spec;
   - significance from a chosen test rather than the coefficient's p;
   - a viewer option to reorder columns by dragging;
   - an "open spec" round trip test for every exported spec;
   - per-row `digits` for estimate rows.
5. The **Publish** button in the viewer depends on the hosting server. That's the other
   chat's work (`docs/notes/rename-and-site.md`). Leave a hook only.

The rename to estrec (being decided in the other chat) will change type strings, file
names and the Python package name. Check with Ted whether it has landed before starting
large edits, so the two chats don't conflict.

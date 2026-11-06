# Rename to estrec, and the website: notes

Handoff notes from the Record viewer chat (f69fc03f, 2026-11-06) for the chat that runs the
rename and sets up the site.

**Status (estrec site chat c6ff6b19, 2026-11-06):** Ted accepted the rename table below as
proposed, with function names kept (`to_estimation()` etc.) and the viewer script renamed
`estrec-table.js`; old-name dfeols records are test output and are ignored. Done in this repo:
1ff3f06 (format strings, suffixes, schema files, `$id`s), 217a5f3 (Python package and CLI),
3127d53 (viewer script), then the prose (spec, README, CHANGELOG). Both PyPI names were free;
Ted created the `estrec` GitHub org and bought `estrec.org` and `estimation-record.org`.
Site answers: one Cloudflare Worker with static assets (no Pages project), R2 bucket
`estrecfiles`, unlisted only, expiry one year after last access, licence CC0 1.0 by default
or CC BY 4.0 / CC BY-SA 4.0.

## Ted's starting point

> "I think i'm leaning towards switching to estrec/estimation-record, as it abbreviates
> better, has a nice noun/verb duality in record/record, and it appears available"

He also asked how to host the viewer so people can upload results, export them and click
**Publish** to get a semi-permanent link to share.

## Proposed rename (awaiting Ted's confirmation)

| Part | Now | Proposed |
|---|---|---|
| Name | "the `estimation` format" | **estrec** ("estimation record") |
| Domain | `estimation-format.github.io/estimation` | **`estrec.org`** (also `estimation-record.org` as a redirect, if cheap) |
| Type strings | `estimation/0.1`, `estimation-collection/0.1`, `estimation-table/0.1` | `estrec/0.1`, `estrec-collection/0.1`, `estrec-table/0.1` |
| File suffixes | `.estimation.json`, `.estimation-collection.json`, `.estimation-table.json` | `.estrec.json`, `.estrec-collection.json`, `.estrec-table.json` |
| Schema `$id`s | `https://estimation-format.github.io/estimation/schema/...` | `https://estrec.org/schema/...` |
| Python | `estimation-format` / `import estimation_format` / CLI `estimation` | `estrec` for all three (fallback if PyPI `estrec` is taken: pip `estrec-format`, `import estrec`) |
| R | `estrec` | unchanged |
| GitHub | org `estimation-format`, repo `estimation` | new org `estrec`, repo transferred to `estrec/estrec` |

Recommendations given to Ted:

- **Make a clean break, with no aliases** for `estimation/0.1`. Nothing is released (no PyPI
  upload; 0.1 is a draft), and the old-name records are test and build files we can
  regenerate.
- **Create a new org and transfer the repo** rather than renaming the org. GitHub redirects
  repos after an org rename but not Pages sites. Either way, the `$id`s move to `estrec.org`
  and stop depending on GitHub.
- The validator uses its bundled schemas and never fetches `$id`s. So the ids can say
  `estrec.org` before the domain works, but the domain must serve `/schema/` before 0.1 is
  announced.

Only Ted can do these:

- register the domain;
- create the GitHub org;
- check that the PyPI name is free;
- push;
- set the repo's Pages custom domain (CNAME and DNS).

### Size (files mentioning each pattern, 2026-11-06)

| Pattern | `estimation/` | dfeols `repo/` |
|---|---|---|
| `estimation/0.1` | 63 | 4 |
| `estimation-collection/0.1` | 19 | 7 |
| `estimation-table/0.1` | 16 | 0 |
| `estimation-format.github.io` | 42 | 1 |
| `estimation_format` | 52 | 24 |
| `.estimation.json` | 76 | 24 |
| `estimation-format` | 62 | 17 |

None of the datasets already pushed to OSCER (`outbox/`) contain records or specs, so they're
unaffected.

### Suggested order

1. Wait for a quiet repo. Check `git status`, and that the Disclosure levels (05fe2fb6) and
   table-tool chats have nothing uncommitted.
2. Do the rename in commits, with tests passing after each:
   - type strings, suffixes, `$id`s, the catalog and the examples (`git mv` the schema
     files);
   - the Python package and CLI, `pyproject.toml` and CI;
   - estrec readers and writers, `inst/levels.json`, the converters (fixest R, reghdfe
     Stata, pyfixest);
   - the viewer (`make_examples.py` and regenerating the generated files);
   - the spec pages, README and CHANGELOG.
3. Then dfeols (`repo/`): move the pin to the renamed package, update its record writer and
   collection kinds, `docs/design/sessions.md`, and its tests. Ted pushes estimation first.
4. Log the decision in STATE.md (Decisions) and update the CLAUDE.md row for `estimation/`
   (Ted edits CLAUDE.md, so propose the text).

## Website and Publish (proposed, not built)

The site has the static viewer and spec pages, plus a small publishing service.

- **Static:** Cloudflare Pages (or GitHub Pages) at `estrec.org`. It serves the spec, the
  schemas at their `$id`s, and the viewer at `/viewer/`. Everything runs in the browser, and
  uploads stay local until the person publishes.
- **Publish:** a Cloudflare Worker with R2 storage.
  - `POST /api/publish` takes `{spec, records}`. The Worker validates them against the
    bundled schemas, size-limits them, assigns a random id and stores the **data**, never
    raw HTML.
  - It returns `/t/<id>` and a delete token.
  - `GET /t/<id>` renders the stored data through one fixed template (the viewer's web-page
    export) under a strict CSP. Since there's no user HTML, there's no stored XSS.
- Protections:
  - identifying fields redacted by default (the same `identifying.js` paths);
  - optional expiry;
  - Turnstile on publish;
  - rate limits per IP;
  - a report link.
- Accounts can come later. A delete token is enough at first.
- Code would live in `server/` in the repo (Worker, wrangler config, tests). Ted creates the
  Cloudflare account and the R2 bucket, and deploys. The chat writes code and tests only.

Open questions for Ted:

- Cloudflare or another host?
- Default expiry: none, or for example one year?
- Should published tables be listed or unlisted? (Proposal: unlisted only.)
- Licence notice for published content?

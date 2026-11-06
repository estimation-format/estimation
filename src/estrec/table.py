# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ted Matherly and the estrec contributors
"""Table specs (`estrec-table/0.1`, spec/table.md): build, read, write, validate and
render regression tables from records.

    import estrec.table as et
    spec = et.new_table(ef.read_collection("table2.estrec-collection.json"),
                        stats=["nobs", "r2_within", {"vcov": "type"}])
    et.write_table(spec, "table2.estrec-table.json")
    print(et.render_table("table2.estrec-table.json", "latex"))

A spec holds no numbers: rendering reads the records it names (by `meta.id`) from its
`sources`, or from records passed in.
"""

from __future__ import annotations

import html
import json
import math
import os
import re
import uuid
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from .collection import is_collection, iter_members, loads_collection, member_sha256
from .records import PACKAGED_SCHEMAS, Issue, jsonschema_check, loads
from .views import _num, glance, pick_vcov, tidy, vcov_label

TABLE_SCHEMA = "estrec-table/0.1"
DEFAULT_STARS = [0.1, 0.05, 0.01]
STAT_LABELS = {
    "nobs": "N",
    "r2": "R²",
    "adj_r2": "Adj. R²",
    "r2_within": "Within R²",
    "adj_r2_within": "Adj. within R²",
    "pseudo_r2": "Pseudo R²",
    "aic": "AIC",
    "bic": "BIC",
    "log_lik": "Log lik.",
    "rmse": "RMSE",
    "f_stat": "F",
}


# lines under each estimate (spec/table.md section 5)
NAMED_LINES = {
    "std_error": "({std_error})",
    "statistic": "({statistic})",
    "p_value": "[{p_value}]",
    "conf_int": "[{conf_low}, {conf_high}]",
}
PLACEHOLDERS = ("estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high")
_PLACEHOLDER = re.compile(r"\{([^{}]*)\}")
_NAMED_NOTES = {
    "std_error": "Standard errors in parentheses.",
    "statistic": "Test statistics in parentheses.",
    "p_value": "p-values in brackets.",
    "conf_int": "Confidence intervals in brackets.",
}
_WORDS = {
    "estimate": "estimate",
    "std_error": "standard error",
    "statistic": "test statistic",
    "p_value": "p-value",
    "conf_low": "lower bound",
    "conf_high": "upper bound",
}


def uncertainty_lines(spec: dict) -> list[str]:
    """The templates for the lines under each estimate: `uncertainty` as a name, a list of
    names and templates, or None (no lines)."""
    unc = spec.get("uncertainty", "std_error")
    if unc is None:
        return []
    items = [unc] if isinstance(unc, str) else list(unc)
    return [NAMED_LINES.get(x, x) for x in items]


def _line_issues(spec: dict) -> list[Issue]:
    unc = spec.get("uncertainty", "std_error")
    if unc is None:
        return []
    items = [unc] if isinstance(unc, str) else unc
    if not isinstance(items, list):
        return [Issue("error", "uncertainty", "a name, a list of names and templates, or null")]
    out = []
    for j, x in enumerate(items):
        path = "uncertainty" if isinstance(unc, str) else f"uncertainty[{j}]"
        if not isinstance(x, str):
            out.append(Issue("error", path, "a name or a template string"))
        elif x in NAMED_LINES:
            continue
        elif "{" not in x:
            out.append(
                Issue("error", path, f"{x!r} is neither a name ({', '.join(NAMED_LINES)}) nor a template")
            )
        else:
            bad = [m for m in _PLACEHOLDER.findall(x) if m not in PLACEHOLDERS]
            if bad:
                out.append(
                    Issue("error", path, f"unknown placeholder {{{bad[0]}}}; use {', '.join(PLACEHOLDERS)}")
                )
            elif not _PLACEHOLDER.search(x):
                out.append(Issue("error", path, "a template needs at least one placeholder"))
    return out


def _uncertainty_note(spec: dict, lines: list[str]) -> str | None:
    unc = spec.get("uncertainty", "std_error")
    if unc is None or not lines:
        return None
    if isinstance(unc, str) and unc in _NAMED_NOTES:
        return _NAMED_NOTES[unc]
    parts = []
    for t in lines:
        t = t.replace("{conf_low}, {conf_high}", "confidence interval")
        parts.append(_PLACEHOLDER.sub(lambda m: _WORDS.get(m.group(1), m.group(1)), t))
    return "Under each estimate: " + "; ".join(parts) + "."


# ---------------------------------------------------------------- records


class _Found:
    __slots__ = ("member", "record", "source")

    def __init__(self, record: dict, member: dict | None, source: str | None):
        self.record, self.member, self.source = record, member, source


def _records_in(path: Path) -> list[tuple[dict, dict | None]]:
    """(record, member entry) for a record file, a folder of records, or a collection."""
    if path.is_dir():
        return [(loads(f.read_bytes()), None) for f in sorted(path.glob("*.estrec.json"))]
    data = path.read_bytes()
    doc = json.loads(data)
    if is_collection(doc):
        coll = loads_collection(data)
        out = []
        for i, m, rec in iter_members(coll, path.parent):
            if rec is None:
                raise ValueError(f"{path}: members[{i}]: record not found")
            out.append((rec, m))
        return out
    return [(loads(data), None)]


def _as_records(records: Any) -> list[tuple[dict, dict | None]]:
    """Records given directly: a record, a list or {label: record} mapping, or a collection."""
    if records is None:
        return []
    if is_collection(records):
        return [(r, m) for _, m, r in iter_members(records) if r is not None]
    if isinstance(records, Mapping) and records.get("schema") == "estrec/0.1":
        return [(records, None)]
    if isinstance(records, Mapping):
        return [(r, {"label": str(k)}) for k, r in records.items()]
    return [(r, None) for r in records]


def index_records(
    spec: dict, base_dir: str | os.PathLike | None = None, records: Any = None
) -> tuple[dict[tuple[str | None, str], _Found], list[Issue]]:
    """The records a spec can use, by (source id, meta.id) and (None, meta.id): those passed
    in, then each source's under `base_dir` (the spec's folder)."""
    found: dict[tuple[str | None, str], _Found] = {}
    issues: list[Issue] = []

    def add(rec, member, src):
        rid = (rec.get("meta") or {}).get("id")
        if not rid:
            return
        f = _Found(rec, member, src)
        found.setdefault((src, rid), f)
        found.setdefault((None, rid), f)

    for rec, m in _as_records(records):
        add(rec, m, None)
    base = Path(base_dir) if base_dir is not None else None
    for i, s in enumerate(spec.get("sources") or []):
        if base is None:
            continue
        p = base / s.get("path", "")
        try:
            for rec, m in _records_in(p):
                add(rec, m, s.get("id"))
        except (OSError, ValueError) as e:
            issues.append(Issue("error", f"sources[{i}]", f"can't read {s.get('path')!r}: {e}"))
    return found, issues


# ---------------------------------------------------------------- building specs


def new_table(
    records: Any,
    *,
    headers: Iterable[str] | None = None,
    rows: Iterable[dict | str] | None = None,
    stats: Iterable[dict | str] | None = ("nobs", "r2", {"vcov": "type"}),
    uncertainty: str | list[str] | None = "std_error",
    stars: list[float] | None = DEFAULT_STARS,
    title: str | None = None,
    sources: Iterable[dict] | None = None,
    pin: bool = False,
    fixed_effects: bool = True,
    **extra: Any,
) -> dict:
    """A spec with one column per record (a list, a {label: record} mapping or a collection),
    in order. `stats` entries may be metric names; `fixed_effects=True` adds a row per fixed
    effect any record has; `pin=True` records each record's sha256."""
    items = _as_records(records)
    if not items:
        raise ValueError("no records")
    heads = list(headers) if headers is not None else None
    cols = []
    for i, (rec, m) in enumerate(items):
        col = {"record": rec["meta"]["id"]}
        h = heads[i] if heads else ((m or {}).get("label") or f"({i + 1})")
        col["header"] = str(h)
        if pin:
            col["sha256"] = member_sha256(rec)
        cols.append(col)
    st = [{"metric": s} if isinstance(s, str) else dict(s) for s in (stats or [])]
    if fixed_effects:
        seen = []
        for rec, _ in items:
            for fe in (rec.get("specification") or {}).get("fixed_effects") or []:
                if fe not in seen:
                    seen.append(fe)
        st += [{"fixed_effect": fe, "label": f"FE: {fe}"} for fe in seen]
    spec = {
        "schema": TABLE_SCHEMA,
        "meta": {"id": str(uuid.uuid4()), "created": _now(), "producer": _producer()},
    }
    if title:
        spec["title"] = title
    if sources:
        spec["sources"] = list(sources)
    spec["columns"] = cols
    if rows:
        spec["rows"] = [{"term": r} if isinstance(r, str) else dict(r) for r in rows]
    spec["uncertainty"] = uncertainty
    if stars:
        spec["stars"] = list(stars)
    if st:
        spec["stats"] = st
    spec.update(extra)
    return spec


def _now() -> str:
    import datetime as _dt

    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _producer() -> dict:
    from . import __version__

    return {"name": "estrec", "version": __version__}


def read_table(path: str | os.PathLike) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_table(spec: dict, path: str | os.PathLike) -> Path:
    path = Path(path)
    path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


# ---------------------------------------------------------------- validation


def _schema_issues(spec: dict) -> list[Issue]:
    try:
        check = jsonschema_check(PACKAGED_SCHEMAS / "estrec-table-0.1.json")
    except ImportError:
        return []
    return check(spec)


def _structural(spec: dict) -> list[Issue]:
    out = []
    if spec.get("schema") != TABLE_SCHEMA:
        out.append(Issue("error", "schema", f"expected {TABLE_SCHEMA!r}"))
    cols = spec.get("columns")
    if not isinstance(cols, list) or not cols:
        out.append(Issue("error", "columns", "at least one column"))
        cols = []
    ids = [s.get("id") for s in spec.get("sources") or [] if isinstance(s, dict)]
    for d in sorted({i for i in ids if ids.count(i) > 1}):
        out.append(Issue("error", "sources", f"duplicate source id {d!r}"))
    for i, c in enumerate(cols):
        if not isinstance(c, dict) or not c.get("record"):
            out.append(Issue("error", f"columns[{i}]", "a column needs `record` (a meta.id)"))
        elif c.get("source") is not None and c["source"] not in ids:
            out.append(Issue("error", f"columns[{i}].source", f"no source {c['source']!r}"))
    for key in ("keep", "drop"):
        for j, pat in enumerate(spec.get(key) or []):
            try:
                re.compile(pat)
            except re.error as e:
                out.append(Issue("error", f"{key}[{j}]", f"pattern doesn't compile: {e}"))
    out += _line_issues(spec)
    for j, s in enumerate(spec.get("stats") or []):
        if "values" in s and len(s["values"]) != len(cols):
            out.append(
                Issue("error", f"stats[{j}].values", f"{len(s['values'])} values for {len(cols)} columns")
            )
    return out


def validate_table(
    spec: dict,
    *,
    base_dir: str | os.PathLike | None = None,
    records: Any = None,
    schema: str | None = "auto",
) -> list[Issue]:
    """Errors and warnings for a spec (spec/table.md section 9). With `base_dir` or
    `records`, the columns' records are looked up and checked too. `schema="auto"` adds the
    JSON Schema check when jsonschema is installed; None skips it."""
    issues = _structural(spec)
    if schema == "auto":
        issues += _schema_issues(spec)
    if base_dir is None and records is None:
        return issues
    found, read_issues = index_records(spec, base_dir, records)
    issues += read_issues
    recs = []
    for i, c in enumerate(spec.get("columns") or []):
        f = found.get((c.get("source"), c.get("record"))) or found.get((None, c.get("record")))
        if f is None:
            issues.append(Issue("error", f"columns[{i}]", f"record {c.get('record')} not found"))
            recs.append(None)
            continue
        recs.append(f.record)
        if c.get("sha256") and member_sha256(f.record) != c["sha256"]:
            issues.append(
                Issue("warning", f"columns[{i}].sha256", "the record has changed since the table was made")
            )
        if c.get("vcov") is not None:
            try:
                pick_vcov(f.record, c["vcov"])
            except (ValueError, IndexError) as e:
                issues.append(Issue("warning", f"columns[{i}].vcov", str(e)))
    have = [r for r in recs if r is not None]
    terms = {p.get("term") for r in have for p in r.get("parameters") or []}
    for j, row in enumerate(spec.get("rows") or []):
        names = row.get("terms") or [row.get("term")]
        if not any(n in terms for n in names):
            issues.append(Issue("warning", f"rows[{j}]", f"no column has {', '.join(map(str, names))}"))
    for j, s in enumerate(spec.get("stats") or []):
        if "metric" in s:
            m = s["metric"]
            ok = any(
                m in (r.get("metrics") or {}) or (m == "rmse" and "rss" in (r.get("metrics") or {}))
                for r in have
            )
            if not ok:
                issues.append(Issue("warning", f"stats[{j}]", f"no record has metric {m!r}"))
        elif "fixed_effect" in s:
            if not any(
                s["fixed_effect"] in ((r.get("specification") or {}).get("fixed_effects") or []) for r in have
            ):
                issues.append(
                    Issue("warning", f"stats[{j}]", f"no record has fixed effect {s['fixed_effect']!r}")
                )
        elif "test" in s:
            if not any(_find_test(r, s["test"]) for r in have):
                issues.append(Issue("warning", f"stats[{j}]", f"no record has test {s['test']!r}"))
    return issues


# ---------------------------------------------------------------- the table


def _find_test(rec: dict, key: str) -> dict | None:
    tests = rec.get("tests") or []
    return next((t for t in tests if t.get("label") == key), None) or next(
        (t for t in tests if t.get("name") == key), None
    )


def _fixed(x: float, digits: int) -> str:
    """Fixed decimals; "-0.000" shows as "0.000"."""
    if x is None or math.isnan(x):
        return ""
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    s = f"{x:.{digits}f}"
    if s.startswith("-") and float(s) == 0:
        s = s[1:]
    return s


def _stat_value(x: Any, digits: int, thousands: str) -> str:
    if x is None:
        return ""
    if isinstance(x, bool):
        return "Yes" if x else "No"
    if isinstance(x, str):
        return x
    x = float(x)
    if math.isnan(x):
        return ""
    if math.isfinite(x) and x == int(x) and abs(x) < 1e15:
        s = f"{int(x):,}"
        return s.replace(",", thousands)
    return _fixed(x, digits)


def _p_value(p: float, digits: int, style: str) -> str:
    """A p-value: fixed decimals ("0.000"), or with style "less_than", "<0.001" below the
    smallest value the decimals can show."""
    if p is None or math.isnan(p):
        return ""
    if style == "less_than" and p < 10.0**-digits:
        return "<" + _fixed(10.0**-digits, digits)
    return _fixed(p, digits)


def _fill(template: str, row: dict, digits: int, p_digits: int, p_style: str, missing: str) -> str:
    """A line under an estimate: the template with its placeholders filled; `missing` when
    any value it needs is missing."""
    vals = {}
    for name in _PLACEHOLDER.findall(template):
        x = row.get(name, math.nan)
        if x is None or math.isnan(x):
            return missing
        vals[name] = _p_value(x, p_digits, p_style) if name == "p_value" else _fixed(x, digits)
    return _PLACEHOLDER.sub(lambda m: vals[m.group(1)], template)


def _stars(p: float, thresholds: list[float], symbols: list[str]) -> str:
    if p is None or math.isnan(p):
        return ""
    out = ""
    for t, s in zip(thresholds, symbols):
        if p < t:
            out = s
    return out


def build_table(spec: dict, *, base_dir: str | os.PathLike | None = None, records: Any = None) -> dict:
    """The table as cells: {"title", "header": [..], "column_records": [meta.id per column],
    "rows": [{"label", "cells", "kind"}], "notes": [..], "warnings": [..]}. `kind` is "estimate", "uncertainty" or "stat". Raises
    ValueError on errors (spec/table.md section 9)."""
    issues = validate_table(spec, base_dir=base_dir, records=records, schema=None)
    errors = [i for i in issues if i.level == "error"]
    if errors:
        raise ValueError("; ".join(map(str, errors)))
    found, _ = index_records(spec, base_dir, records)
    fmt = spec.get("format") or {}
    digits = fmt.get("digits", 3)
    thousands = fmt.get("thousands", ",")
    missing = fmt.get("missing", "")
    stars = spec.get("stars") or []
    symbols = fmt.get("star_symbols") or ["*" * (i + 1) for i in range(len(stars))]
    lines = uncertainty_lines(spec)
    p_digits = fmt.get("p_digits", digits)
    p_style = fmt.get("p_style", "fixed")

    cols = []
    for i, c in enumerate(spec["columns"]):
        f = found.get((c.get("source"), c["record"])) or found[(None, c["record"])]
        rows = tidy(f.record, vcov=c.get("vcov"), component=c.get("component"))
        if c.get("response"):
            rows = [r for r in rows if r.get("response") == c["response"]]
        header = c.get("header")
        if header is None:
            header = (
                (f.member or {}).get("label") or (f.record.get("meta") or {}).get("title") or f"({i + 1})"
            )
        cols.append(
            {
                "spec": c,
                "found": f,
                "tidy": {r["term"]: r for r in rows},
                "order": [r["term"] for r in rows],
                "header": header,
            }
        )

    # rows: listed first, then the unlisted terms by first appearance, filtered by keep/drop
    listed = []
    taken = set()
    for row in spec.get("rows") or []:
        names = row.get("terms") or [row["term"]]
        listed.append((row.get("label") or names[0], names))
        taken.update(names)
    if spec.get("keep_unlisted", True):
        keep = [re.compile(p) for p in spec.get("keep") or []]
        drop = [re.compile(p) for p in spec.get("drop") or []]
        seen = []
        for c in cols:
            for t in c["order"]:
                if t in taken or t in seen:
                    continue
                if keep and not any(k.search(t) for k in keep):
                    continue
                if any(d.search(t) for d in drop):
                    continue
                seen.append(t)
        listed += [(t, [t]) for t in seen]

    out_rows = []
    for label, names in listed:
        est = []
        below: list[list[str]] = [[] for _ in lines]
        for c in cols:
            r = next((c["tidy"][n] for n in names if n in c["tidy"]), None)
            if r is None:
                est.append(missing)
                for b in below:
                    b.append(missing)
                continue
            est.append(_fixed(r["estimate"], digits) + _stars(r["p_value"], stars, symbols))
            for b, t in zip(below, lines):
                b.append(_fill(t, r, digits, p_digits, p_style, missing))
        out_rows.append({"label": label, "cells": est, "kind": "estimate"})
        out_rows += [{"label": "", "cells": b, "kind": "uncertainty"} for b in below]

    for s in spec.get("stats") or []:
        d = s.get("digits", digits)
        cells = []
        if "values" in s:
            cells = [str(v) for v in s["values"]]
            label = s["label"]
        elif "metric" in s:
            m = s["metric"]
            label = s.get("label") or STAT_LABELS.get(m, m)
            for c in cols:
                g = glance(c["found"].record, vcov=c["spec"].get("vcov"), metrics="all")
                if m == "rmse" and "rmse" not in g:
                    g["rmse"] = glance(c["found"].record, metrics="table").get("rmse")
                v = g.get(m)
                cells.append(missing if v is None else _stat_value(v, d, thousands))
        elif "vcov" in s:
            label = s.get("label") or ("Std. errors" if s["vcov"] == "type" else "Clusters")
            for c in cols:
                v = pick_vcov(c["found"].record, c["spec"].get("vcov"))
                if v is None:
                    cells.append(missing)
                elif s["vcov"] == "type":
                    cells.append(vcov_label(v))
                else:
                    n = v.get("n_clusters") or {}
                    vals = [_stat_value(x, 0, thousands) for x in n.values()] if isinstance(n, dict) else []
                    cells.append(" / ".join(vals) or missing)
        elif "fixed_effect" in s:
            fe = s["fixed_effect"]
            label = s.get("label") or f"FE: {fe}"
            yes, no = fmt.get("fe_yes", "Yes"), fmt.get("fe_no", "")
            for c in cols:
                has = fe in ((c["found"].record.get("specification") or {}).get("fixed_effects") or [])
                cells.append(yes if has else no)
        elif "test" in s:
            label = s.get("label") or s["test"]
            which = s.get("value", "statistic")
            for c in cols:
                t = _find_test(c["found"].record, s["test"])
                v = _num(t.get(which)) if t else math.nan
                if math.isnan(v):
                    cells.append(missing)
                elif which == "p_value":
                    cells.append(_p_value(v, s.get("digits", p_digits), p_style))
                else:
                    cells.append(_fixed(v, d))
        out_rows.append({"label": label, "cells": cells, "kind": "stat"})

    notes = list(spec.get("notes") or [])
    if stars:
        notes.append(", ".join(f"{sym} p < {t:g}" for t, sym in zip(stars, symbols)))
    note = _uncertainty_note(spec, lines)
    if note:
        notes.append(note)
    return {
        "title": spec.get("title"),
        "header": [c["header"] for c in cols],
        "column_records": [c["found"].record["meta"]["id"] for c in cols],
        "rows": out_rows,
        "notes": notes,
        "warnings": [str(i) for i in issues if i.level == "warning"],
    }


# ---------------------------------------------------------------- rendering

_LATEX = {
    "&": r"\&",
    "%": r"\%",
    "$": r"\$",
    "#": r"\#",
    "_": r"\_",
    "{": r"\{",
    "}": r"\}",
    "~": r"\textasciitilde{}",
    "^": r"\textasciicircum{}",
    "\\": r"\textbackslash{}",
}


def _tex(s: str) -> str:
    return "".join(_LATEX.get(ch, ch) for ch in s)


def _render_markdown(t: dict) -> str:
    def esc(s):
        return s.replace("\\", "\\\\").replace("|", "\\|").replace("*", "\\*")

    lines = []
    if t["title"]:
        lines += [f"**{esc(t['title'])}**", ""]
    lines.append("| | " + " | ".join(map(esc, t["header"])) + " |")
    lines.append("|---|" + "---:|" * len(t["header"]))
    for r in t["rows"]:
        lines.append(f"| {esc(r['label'])} | " + " | ".join(map(esc, r["cells"])) + " |")
    if t["notes"]:
        lines += [""] + [f"{esc(n)}  " for n in t["notes"]]
    return "\n".join(lines).rstrip() + "\n"


def _render_latex(t: dict, escape: bool = True) -> str:
    e = _tex if escape else (lambda s: s)
    n = len(t["header"])
    lines = ["\\begin{table}[htbp]", "\\centering"]
    if t["title"]:
        lines.append(f"\\caption{{{e(t['title'])}}}")
    lines += [f"\\begin{{tabular}}{{l{'c' * n}}}", "\\toprule"]
    lines.append(" & " + " & ".join(map(e, t["header"])) + " \\\\")
    lines.append("\\midrule")
    prev = None
    for r in t["rows"]:
        if r["kind"] == "stat" and prev != "stat":
            lines.append("\\midrule")
        lines.append(f"{e(r['label'])} & " + " & ".join(map(e, r["cells"])) + " \\\\")
        prev = r["kind"]
    lines.append("\\bottomrule")
    lines.append("\\end{tabular}")
    if t["notes"]:
        lines.append("\\par\\smallskip{\\footnotesize " + " ".join(map(e, t["notes"])) + "}")
    lines.append("\\end{table}")
    return "\n".join(lines) + "\n"


def _render_html(t: dict) -> str:
    h = html.escape
    out = ['<table class="estrec-table">']
    if t["title"]:
        out.append(f"<caption>{h(t['title'])}</caption>")
    out.append("<thead><tr><th></th>" + "".join(f"<th>{h(x)}</th>" for x in t["header"]) + "</tr></thead>")
    out.append("<tbody>")
    prev = None
    for r in t["rows"]:
        cls = r["kind"] + (" first-stat" if r["kind"] == "stat" and prev != "stat" else "")
        out.append(
            f'<tr class="{cls}"><th>{h(r["label"])}</th>'
            + "".join(f"<td>{h(x)}</td>" for x in r["cells"])
            + "</tr>"
        )
        prev = r["kind"]
    out.append("</tbody>")
    if t["notes"]:
        out.append(
            f'<tfoot><tr><td colspan="{len(t["header"]) + 1}">'
            + "<br>".join(map(h, t["notes"]))
            + "</td></tr></tfoot>"
        )
    out.append("</table>")
    return "\n".join(out) + "\n"


def _render_csv(t: dict) -> str:
    import csv
    import io

    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow([""] + t["header"])
    for r in t["rows"]:
        w.writerow([r["label"]] + r["cells"])
    return buf.getvalue()


def _render_text(t: dict) -> str:
    rows = [[""] + t["header"]] + [[r["label"]] + r["cells"] for r in t["rows"]]
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]

    def line(r):
        return "  ".join(
            c.ljust(widths[0]) if i == 0 else c.rjust(widths[i]) for i, c in enumerate(r)
        ).rstrip()

    rule = "  ".join("-" * w for w in widths)
    out = []
    if t["title"]:
        out.append(t["title"])
    out += [line(rows[0]), rule]
    prev = None
    for r, src in zip(rows[1:], t["rows"]):
        if src["kind"] == "stat" and prev != "stat":
            out.append(rule)
        out.append(line(r))
        prev = src["kind"]
    out += [rule, *t["notes"]]
    return "\n".join(out) + "\n"


# Word: inline styles only (Word drops classes and style sheets when pasting), borders as a
# journal table's three rules, numbers centred, no font family (the document's is kept).
_WORD_RULE = "solid windowtext"
_WORD_CELL = "padding:0 5.4pt;border:none;white-space:nowrap"


def _word_cell(text: str, *, left: bool, top: str = "", bottom: str = "", pad_top: bool = False) -> str:
    style = _WORD_CELL + (";text-align:left" if left else ";text-align:center")
    if top:
        style += f";border-top:{top} {_WORD_RULE}"
    if bottom:
        style += f";border-bottom:{bottom} {_WORD_RULE}"
    if pad_top:
        style += ";padding-top:3pt"
    return f'<td style="{style}">{html.escape(text)}</td>'


def _render_word(t: dict) -> str:
    """A whole HTML document that Word, Google Docs, LibreOffice and Excel paste or open as a
    formatted table (the viewer's Copy for Word puts it on the clipboard)."""
    h = html.escape
    title = t["title"] or "Estimation table"
    out = [
        "<!doctype html>",
        '<html><head><meta charset="utf-8">',
        f"<title>{h(title)}</title></head><body>",
    ]
    if t["title"]:
        out.append(f'<p style="margin:0 0 6pt 0"><b>{h(t["title"])}</b></p>')
    out.append('<table style="border-collapse:collapse;border:none;font-size:10pt">')
    out.append(
        "<tr>"
        + "".join(
            _word_cell(x, left=i == 0, top="1.5pt", bottom=".75pt") for i, x in enumerate([""] + t["header"])
        )
        + "</tr>"
    )
    prev = None
    last = len(t["rows"]) - 1
    for k, r in enumerate(t["rows"]):
        top = ".75pt" if r["kind"] == "stat" and prev != "stat" else ""
        bottom = "1.5pt" if k == last else ""
        pad = r["kind"] == "estimate" and k > 0
        out.append(
            "<tr>"
            + "".join(
                _word_cell(x, left=i == 0, top=top, bottom=bottom, pad_top=pad)
                for i, x in enumerate([r["label"]] + r["cells"])
            )
            + "</tr>"
        )
        prev = r["kind"]
    out.append("</table>")
    for n in t["notes"]:
        out.append(f'<p style="margin:3pt 0 0 0;font-size:9pt">{h(n)}</p>')
    out.append("</body></html>")
    return "\n".join(out) + "\n"


RENDERERS = {
    "markdown": _render_markdown,
    "latex": _render_latex,
    "html": _render_html,
    "csv": _render_csv,
    "text": _render_text,
    "word": _render_word,
}


def render(table: dict, format: str = "text", **options: Any) -> str:
    """A built table (`build_table`) as text: "text", "markdown", "latex", "html", "csv"
    or "word" (an HTML document styled inline, for pasting into or opening in Word).
    LaTeX takes `escape=False` to keep labels as written (for math in labels)."""
    if format not in RENDERERS:
        raise ValueError(f"format is one of {', '.join(RENDERERS)}")
    return RENDERERS[format](table, **options)


def render_table(
    spec: dict | str | os.PathLike,
    format: str = "text",
    *,
    base_dir: str | os.PathLike | None = None,
    records: Any = None,
    **options: Any,
) -> str:
    """Build and render a spec (a dict or a path; a path's folder is `base_dir`)."""
    if not isinstance(spec, dict):
        path = Path(spec)
        spec = read_table(path)
        base_dir = path.parent if base_dir is None else base_dir
    return render(build_table(spec, base_dir=base_dir, records=records), format, **options)


def to_great_table(table: dict):
    """A built table as a great_tables GT object (needs great_tables and pandas or polars)."""
    try:
        import great_tables as gt
    except ImportError as e:  # pragma: no cover - depends on the environment
        raise ImportError("to_great_table needs great_tables: pip install great_tables") from e
    try:
        import polars as pl

        frame = pl.DataFrame(
            {
                "": [r["label"] for r in table["rows"]],
                **{h: [r["cells"][i] for r in table["rows"]] for i, h in enumerate(table["header"])},
            }
        )
    except ImportError:
        import pandas as pd

        frame = pd.DataFrame(
            {
                "": [r["label"] for r in table["rows"]],
                **{h: [r["cells"][i] for r in table["rows"]] for i, h in enumerate(table["header"])},
            }
        )
    g = gt.GT(frame)
    if table["title"]:
        g = g.tab_header(title=table["title"])
    for n in table["notes"]:
        g = g.tab_source_note(n)
    return g


# ---------------------------------------------------------------- command line


def add_arguments(p) -> None:
    """The `table` options, for the `estrec` CLI and `python -m estrec.table`."""
    p.add_argument("spec", help="an *.estrec-table.json file")
    p.add_argument("--format", "-f", default="text", choices=sorted(RENDERERS))
    p.add_argument("--check", action="store_true", help="validate only; exit 1 on errors")
    p.add_argument("-o", "--output", help="write to a file instead of printing")


def run(a) -> int:
    import sys

    path = Path(a.spec)
    try:
        spec = read_table(path)
    except (OSError, ValueError) as e:
        print(f"estrec table: {e}", file=sys.stderr)
        return 1
    if a.check:
        issues = validate_table(spec, base_dir=path.parent)
        for i in issues:
            print(i)
        return 1 if any(i.level == "error" for i in issues) else 0
    try:
        t = build_table(spec, base_dir=path.parent)
    except ValueError as e:
        print(f"estrec table: {e}", file=sys.stderr)
        return 1
    for w in t["warnings"]:
        print(w, file=sys.stderr)
    text = render(t, a.format)
    if a.output:
        Path(a.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


def main(argv: list[str] | None = None) -> int:
    import argparse

    p = argparse.ArgumentParser(prog="estrec table", description="Render or check a table spec.")
    add_arguments(p)
    return run(p.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "TABLE_SCHEMA",
    "build_table",
    "index_records",
    "new_table",
    "read_table",
    "render",
    "render_table",
    "to_great_table",
    "validate_table",
    "write_table",
]

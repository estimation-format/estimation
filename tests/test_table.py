"""Table specs (spec/table.md): building, validating and rendering."""

import copy
import html
import json

import pytest

import estrec as ef
from estrec import records as est
from estrec import table as et

EXAMPLES = est.PACKAGED_SCHEMAS / "examples"
SPEC = EXAMPLES / "paper.estrec-table.json"
SESSION = EXAMPLES / "session.estrec-collection.json"


def spec():
    return et.read_table(SPEC)


def cells(t, label):
    return next(r["cells"] for r in t["rows"] if r["label"] == label)


def test_example_builds():
    t = et.build_table(spec(), base_dir=EXAMPLES)
    assert t["header"] == ["(1)", "(2)", "(3)"]
    assert [r["label"] for r in t["rows"] if r["kind"] == "estimate"] == ["Weight (1000 lbs)", "Horsepower"]
    assert cells(t, "Weight (1000 lbs)")[0] == "-3.206***"
    assert cells(t, "Horsepower")[0] == ""  # not in column (1)
    assert cells(t, "N") == ["32", "32", "32"]
    assert cells(t, "Std. errors") == ["iid", "HC1", "HC1"]
    assert cells(t, "Cylinders FE") == ["Yes", "Yes", "Yes"]
    assert cells(t, "Controls") == ["No", "No", "qsec"]
    assert "* p < 0.1, ** p < 0.05, *** p < 0.01" in t["notes"]
    assert t["warnings"] == []


@pytest.mark.parametrize("fmt", sorted(et.RENDERERS))
def test_example_renders(fmt):
    out = et.render_table(SPEC, fmt)
    assert "3.206" in out


def test_validates_against_schema():
    pytest.importorskip("jsonschema")
    assert et.validate_table(spec()) == []
    bad = spec()
    bad["stats"].append({"metric": "nobs", "fixed_effect": "cyl"})  # two kinds in one row
    bad["uncertainty"] = "variance"
    assert len([i for i in et.validate_table(bad) if i.level == "error"]) >= 2


def test_structural_errors():
    s = spec()
    s["columns"][0]["source"] = "nowhere"
    s["drop"] = ["("]
    s["stats"][-1]["values"] = ["only one"]
    s["sources"].append({"id": "paper", "path": "x.json"})
    msgs = [i.message for i in et.validate_table(s, schema=None) if i.level == "error"]
    assert any("no source 'nowhere'" in m for m in msgs)
    assert any("doesn't compile" in m for m in msgs)
    assert any("1 values for 3 columns" in m for m in msgs)
    assert any("duplicate source id" in m for m in msgs)


def test_missing_record_is_an_error():
    s = spec()
    s["columns"][1]["record"] = "00000000-0000-4000-8000-000000000000"
    assert any("not found" in i.message for i in et.validate_table(s, base_dir=EXAMPLES))
    with pytest.raises(ValueError, match="not found"):
        et.build_table(s, base_dir=EXAMPLES)


def test_warnings():
    s = spec()
    s["columns"][0]["sha256"] = "0" * 64
    s["columns"][1]["vcov"] = "CRV3"
    s["rows"].append({"term": "nope"})
    s["stats"] += [{"metric": "auc"}, {"fixed_effect": "gear"}, {"test": "sargan"}]
    msgs = [i.message for i in et.validate_table(s, base_dir=EXAMPLES, schema=None) if i.level == "warning"]
    assert any("has changed" in m for m in msgs)
    assert any("no vcov 'CRV3'" in m for m in msgs)
    assert any("no column has nope" in m for m in msgs)
    assert any("metric 'auc'" in m for m in msgs)
    assert any("fixed effect 'gear'" in m for m in msgs)
    assert any("test 'sargan'" in m for m in msgs)


def test_pinned_hash_matches():
    s = spec()
    recs = {
        r["meta"]["id"]: r
        for _, _, r in ef.iter_members(ef.read_collection(EXAMPLES / "paper.estrec-collection.json"))
    }
    for c in s["columns"]:
        c["sha256"] = ef.member_sha256(recs[c["record"]])
    assert [i for i in et.validate_table(s, base_dir=EXAMPLES, schema=None) if i.level != "info"] == []


def test_rows_keep_drop_and_shared_rows():
    s = spec()
    s["drop"] = []
    t = et.build_table(s, base_dir=EXAMPLES)
    assert [r["label"] for r in t["rows"] if r["kind"] == "estimate"] == [
        "Weight (1000 lbs)",
        "Horsepower",
        "qsec",
    ]
    s["keep"] = ["^q"]
    s["rows"] = [{"terms": ["hp", "wt"], "label": "hp or wt"}]  # first one each column has
    t = et.build_table(s, base_dir=EXAMPLES)
    assert [r["label"] for r in t["rows"] if r["kind"] == "estimate"] == ["hp or wt", "qsec"]
    assert cells(t, "hp or wt")[0].startswith("-3.206")  # column (1) has only wt
    assert cells(t, "hp or wt")[1].startswith("-0.023")
    s["keep_unlisted"] = False
    t = et.build_table(s, base_dir=EXAMPLES)
    assert [r["label"] for r in t["rows"] if r["kind"] == "estimate"] == ["hp or wt"]


@pytest.mark.parametrize(
    "unc,second",
    [
        ("std_error", "(0.754)"),
        ("statistic", "(-4.252)"),
        ("p_value", "[0.000]"),
        ("conf_int", "[-4.750, -1.661]"),
    ],
)
def test_uncertainty(unc, second):
    s = spec()
    s["uncertainty"] = unc
    t = et.build_table(s, base_dir=EXAMPLES)
    assert t["rows"][1]["cells"][0] == second


def test_no_uncertainty_no_stars():
    s = spec()
    s["uncertainty"] = None
    s["stars"] = None
    t = et.build_table(s, base_dir=EXAMPLES)
    assert t["rows"][1]["kind"] == "estimate" and t["rows"][0]["cells"][0] == "-3.206"
    assert not any("p <" in n for n in t["notes"])


def test_column_vcov_and_clusters():
    coll = ef.read_collection(SESSION)
    s = et.new_table(coll, stats=["nobs", {"vcov": "type"}, {"vcov": "n_clusters"}])
    s["columns"].append(dict(s["columns"][0], header="iid", vcov="iid"))
    t = et.build_table(s, records=coll)
    rec = next(r for _, _, r in ef.iter_members(coll))
    iid = ef.tidy(rec, vcov="iid")[0]
    assert t["header"] == ["(1)", "(2)", "(3)"]
    s["head"] = ["label"]
    assert et.build_table(s, records=coll)["head"][0]["cells"] == ["firm", "firm_year", "iid"]
    assert t["rows"][1]["cells"][2] == f"({iid['std_error']:.3f})"
    assert cells(t, "Std. errors") == ["by: firm", "by: firm", "iid"]
    assert cells(t, "Clusters")[0] == "980" and cells(t, "Clusters")[2] == ""
    assert cells(t, "FE: firm") == ["Yes", "Yes", "Yes"]


def test_new_table_and_round_trip(tmp_path):
    coll = ef.read_collection(EXAMPLES / "paper.estrec-collection.json")
    s = et.new_table(coll, title="T", pin=True, sources=[{"id": "p", "path": "paper.estrec-collection.json"}])
    assert all("header" not in c for c in s["columns"])
    assert all(len(c["sha256"]) == 64 for c in s["columns"])
    path = et.write_table(s, tmp_path / "t.estrec-table.json")
    assert et.read_table(path) == json.loads(json.dumps(s))
    assert et.render_table(s, "text", base_dir=EXAMPLES).startswith("T\n")
    if pytest.importorskip("jsonschema"):
        assert et.validate_table(s) == []


def test_latex_escapes_and_rules():
    s = spec()
    s["title"] = "Fares & HHI_1 (100%)"
    out = et.render_table(s, "latex", base_dir=EXAMPLES)
    assert r"Fares \& HHI\_1 (100\%)" in out and out.count(r"\midrule") == 2
    s["rows"][0]["label"] = r"$\beta$"
    assert r"$\beta$" in et.render_table(s, "latex", base_dir=EXAMPLES, escape=False)


def test_html_escapes():
    s = spec()
    s["rows"][0]["label"] = "<b>wt</b>"
    out = et.render_table(s, "html", base_dir=EXAMPLES)
    assert "&lt;b&gt;wt&lt;/b&gt;" in out and '<tr class="stat first-stat">' in out


def test_digits_and_format():
    s = spec()
    s["format"] = {"digits": 2, "thousands": " ", "fe_yes": "X", "star_symbols": ["+", "*", "**"]}
    t = et.build_table(s, base_dir=EXAMPLES)
    assert cells(t, "Weight (1000 lbs)")[0] == "-3.21**" and cells(t, "Cylinders FE")[0] == "X"
    assert "+ p < 0.1, * p < 0.05, ** p < 0.01" in t["notes"]


def test_cli(tmp_path, capsys):
    assert et.main([str(SPEC), "--format", "csv"]) == 0
    assert capsys.readouterr().out.splitlines()[0] == ",(1),(2),(3)"
    assert et.main([str(SPEC), "--check"]) == 0
    out = tmp_path / "t.tex"
    assert et.main([str(SPEC), "-f", "latex", "-o", str(out)]) == 0 and r"\toprule" in out.read_text()
    bad = copy.deepcopy(spec())
    bad["columns"][0]["record"] = "missing"
    p = tmp_path / "bad.estrec-table.json"
    p.write_text(json.dumps(bad))
    assert et.main([str(p)]) == 1


def test_great_tables():
    pytest.importorskip("great_tables")
    g = et.to_great_table(et.build_table(spec(), base_dir=EXAMPLES))
    assert "3.206" in g.as_raw_html()


def test_estimation_cli_subcommands(capsys):
    from estrec.records import main

    assert main(["table", str(SPEC), "-f", "markdown"]) == 0
    assert "| Weight (1000 lbs) |" in capsys.readouterr().out
    assert main(["show", str(EXAMPLES / "paper.estrec-collection.json")]) == 0
    assert capsys.readouterr().out.split("\n")[0].split() == ["baseline", "horsepower", "full"]
    assert main(["validate", str(SPEC)]) == 0
    assert "valid (0 errors)" in capsys.readouterr().out


def test_several_lines_under_estimates():
    s = spec()
    s["uncertainty"] = ["std_error", "[{p_value}]", "t = {statistic}"]
    t = et.build_table(s, base_dir=EXAMPLES)
    assert [r["kind"] for r in t["rows"][:4]] == ["estimate", "uncertainty", "uncertainty", "uncertainty"]
    assert [r["cells"][0] for r in t["rows"][:4]] == ["-3.206***", "(0.754)", "[0.000]", "t = -4.252"]
    assert t["rows"][5]["cells"][0] == ""  # Horsepower isn't in column (1): every line blank
    assert "Under each estimate: (standard error); [p-value]; t = test statistic." in t["notes"]


@pytest.mark.parametrize(
    "fmt,want",
    [
        ({}, "[0.000]"),
        ({"p_style": "less_than"}, "[<0.001]"),
        ({"p_digits": 4}, "[0.0002]"),
        ({"p_digits": 2, "p_style": "less_than"}, "[<0.01]"),
        ({"p_digits": 4, "p_style": "less_than"}, "[0.0002]"),
    ],
)
def test_p_value_format(fmt, want):
    s = spec()
    s["uncertainty"] = "[{p_value}]"
    s["format"] = {"digits": 3, **fmt}
    t = et.build_table(s, base_dir=EXAMPLES)
    assert t["rows"][1]["cells"][0] == want


def test_p_style_applies_to_test_rows():
    s = spec()
    s["format"] = {"digits": 3, "p_style": "less_than"}
    assert cells(et.build_table(s, base_dir=EXAMPLES), "Wald p") == ["<0.001", "<0.001", "<0.001"]


def test_bad_lines_are_errors():
    s = spec()
    s["uncertainty"] = ["({stderr})", "bogus", "no placeholders {}"]
    msgs = [i.message for i in et.validate_table(s, schema=None) if i.level == "error"]
    assert any("unknown placeholder {stderr}" in m for m in msgs)
    assert any("'bogus' is neither a name" in m for m in msgs)
    assert len(msgs) == 3
    pytest.importorskip("jsonschema")
    ok = spec()
    ok["uncertainty"] = ["std_error", "p = {p_value}"]
    ok["format"] = {"p_digits": 4, "p_style": "less_than"}
    assert et.validate_table(ok) == []


def test_word_render_has_three_rules_and_inline_styles():
    t = et.build_table(spec(), base_dir=EXAMPLES)
    doc = et.render(t, "word")
    assert doc.startswith("<!doctype html>") and doc.rstrip().endswith("</body></html>")
    assert "class=" not in doc and "<style" not in doc  # Word keeps inline styles only
    assert doc.count("border-top:1.5pt") == len(t["header"]) + 1  # top rule over the header
    assert doc.count("border-bottom:1.5pt") == len(t["header"]) + 1  # bottom rule
    n_stat_starts = sum(
        1
        for i, r in enumerate(t["rows"])
        if r["kind"] == "stat" and (i == 0 or t["rows"][i - 1]["kind"] != "stat")
    )
    assert doc.count("border-top:.75pt") == n_stat_starts * (len(t["header"]) + 1)
    for n in t["notes"]:
        assert html.escape(n) in doc


def test_heading_rows_number_then_response_by_default():
    coll = ef.read_collection(EXAMPLES / "paper.estrec-collection.json")
    s = et.new_table(coll)
    t = et.build_table(s, records=coll)
    assert [h["kind"] for h in t["head"]] == ["number", "response"]
    assert t["head"][0]["cells"] == t["header"] == ["(1)", "(2)", "(3)"]
    resp = [", ".join(r["meta"]["responses"]) for _, _, r in ef.iter_members(coll)]
    assert t["head"][1]["cells"] == resp
    s["response_labels"] = {resp[0]: "Miles per gallon"}
    assert et.build_table(s, records=coll)["head"][1]["cells"][0] == "Miles per gallon"


def test_heading_rows_order_and_label_row():
    coll = ef.read_collection(EXAMPLES / "paper.estrec-collection.json")
    s = et.new_table(coll, head=["label", "number"])
    t = et.build_table(s, records=coll)
    assert [h["cells"] for h in t["head"]] == [["baseline", "horsepower", "full"], ["(1)", "(2)", "(3)"]]
    text = et.render(t, "text").splitlines()
    assert "baseline" in text[0] and "(1)" in text[1] and set(text[2]) <= {"-", " "}
    md = et.render(t, "markdown").splitlines()
    assert "baseline" in md[0] and md[1].startswith("|---|") and "(1)" in md[2]
    assert et.render(t, "latex").count(" & (1) & ") == 1
    assert '<tr class="head-label">' in et.render(t, "html")
    assert et.render(t, "csv").splitlines()[:2] == [",baseline,horsepower,full", ",(1),(2),(3)"]
    s["head"] = []
    t = et.build_table(s, records=coll)
    assert t["head"] == [] and "1.5pt" in et.render(t, "word").split("<tr>")[1]
    s["head"] = ["number", "bogus", "number"]
    msgs = [i.path for i in et.validate_table(s, schema=None)]
    assert msgs == ["head[1]", "head[2]"]


def sparkline_table(scale):
    s = spec()
    s["uncertainty"] = ["std_error", {"sparkline": {"color": "#c0392b", "scale": scale}}]
    return et.build_table(s, base_dir=EXAMPLES)


def test_sparkline_rows_carry_intervals_and_text():
    t = sparkline_table("column")
    sp = [r for r in t["rows"] if "sparkline" in r]
    assert sp and all(r["kind"] == "uncertainty" for r in sp)
    m = sp[0]["sparkline"]["marks"][0]
    assert m["low"] < m["estimate"] < m["high"]
    assert sp[0]["cells"][0] == f"[{m['low']:.3f}, {m['high']:.3f}]"  # text formats show the interval
    assert "[" in et.render(t, "text") and "<svg" not in et.render(t, "latex")
    assert any("drawn as a line" in n for n in t["notes"])


def test_sparkline_scales():
    def domains(t):
        sp = [r["sparkline"]["marks"] for r in t["rows"] if "sparkline" in r]
        return [[m and tuple(m["domain"]) for m in row] for row in sp]

    col, row, tab = (domains(sparkline_table(k)) for k in ("column", "row", "table"))
    for j in range(len(col[0])):  # one axis down each column
        assert len({r[j] for r in col if r[j]}) == 1
    for r in row:  # one axis along each row
        assert len({d for d in r if d}) == 1
    assert len({d for r in tab for d in r if d}) == 1
    for d in {d for r in col + row + tab for d in r if d}:
        assert d[0] <= 0 <= d[1]


def test_sparkline_html_and_word():
    t = sparkline_table("column")
    h = et.render(t, "html")
    assert h.count('<td class="spark"><svg') == 5 and 'stroke="#555555"' in h and 'fill="#7c251b"' in h
    w = et.render(t, "word")
    assert w.count('src="data:image/svg+xml;base64,') == 5 and "<svg" not in w


def test_sparkline_validation():
    s = spec()
    s["uncertainty"] = [{"sparkline": {"color": "red", "scale": "diagonal"}}, {"sparkline": 1}]
    paths = [i.path for i in et.validate_table(s, schema=None)]
    assert paths == ["uncertainty[0].sparkline.color", "uncertainty[0].sparkline.scale", "uncertainty[1]"]


def test_no_estimate_row_lines_carry_the_term():
    s = spec()
    s["uncertainty"] = {"sparkline": {}}
    s["estimate"] = False
    t = et.build_table(s, base_dir=EXAMPLES)
    est = [r for r in t["rows"] if r["kind"] != "stat"]
    assert [r["label"] for r in est] == ["Weight (1000 lbs)", "Horsepower"]
    assert all("sparkline" in r and r["kind"] == "estimate" for r in est)
    assert not any("p <" in n for n in t["notes"])  # no stars without estimates
    assert 'class="estimate spark-row"' in et.render(t, "html")
    assert "padding-top:3pt" not in et.render(t, "word")
    s["uncertainty"] = None
    assert [i.path for i in et.validate_table(s, schema=None)] == ["estimate"]
    s["estimate"] = "no"
    assert [i.path for i in et.validate_table(s, schema=None)] == ["estimate"]


def test_event_study_example_is_a_column_of_sparklines():
    t = et.render_table(EXAMPLES / "event-study.estrec-table.json", "html")
    assert t.count("<svg") == 7 and "***" not in t
    built = et.build_table(et.read_table(EXAMPLES / "event-study.estrec-table.json"), base_dir=EXAMPLES)
    assert [r["label"] for r in built["rows"]][:7] == [
        "t \u2212 3",
        "t \u2212 2",
        "t \u2212 1",
        "t",
        "t + 1",
        "t + 2",
        "t + 3",
    ]
    doms = {tuple(r["sparkline"]["marks"][0]["domain"]) for r in built["rows"] if "sparkline" in r}
    assert len(doms) == 1  # one axis down the column
    if pytest.importorskip("jsonschema"):
        assert (
            et.validate_table(et.read_table(EXAMPLES / "event-study.estrec-table.json"), base_dir=EXAMPLES)
            == []
        )

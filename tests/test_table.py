"""Table specs (spec/table.md): building, validating and rendering."""

import copy
import json

import pytest

import estimation_format as ef
from estimation_format import records as est
from estimation_format import table as et

EXAMPLES = est.PACKAGED_SCHEMAS / "examples"
SPEC = EXAMPLES / "paper.estimation-table.json"
SESSION = EXAMPLES / "session.estimation-collection.json"


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
        for _, _, r in ef.iter_members(ef.read_collection(EXAMPLES / "paper.estimation-collection.json"))
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
    assert t["header"] == ["firm", "firm_year", "iid"]
    assert t["rows"][1]["cells"][2] == f"({iid['std_error']:.3f})"
    assert cells(t, "Std. errors") == ["by: firm", "by: firm", "iid"]
    assert cells(t, "Clusters")[0] == "980" and cells(t, "Clusters")[2] == ""
    assert cells(t, "FE: firm") == ["Yes", "Yes", "Yes"]


def test_new_table_and_round_trip(tmp_path):
    coll = ef.read_collection(EXAMPLES / "paper.estimation-collection.json")
    s = et.new_table(
        coll, title="T", pin=True, sources=[{"id": "p", "path": "paper.estimation-collection.json"}]
    )
    assert [c["header"] for c in s["columns"]] == ["baseline", "horsepower", "full"]
    assert all(len(c["sha256"]) == 64 for c in s["columns"])
    path = et.write_table(s, tmp_path / "t.estimation-table.json")
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
    p = tmp_path / "bad.estimation-table.json"
    p.write_text(json.dumps(bad))
    assert et.main([str(p)]) == 1


def test_great_tables():
    pytest.importorskip("great_tables")
    g = et.to_great_table(et.build_table(spec(), base_dir=EXAMPLES))
    assert "3.206" in g.as_raw_html()

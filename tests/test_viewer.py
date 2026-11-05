"""The browser viewer (viewer/): its examples are current, and when node is installed, its
table logic (viewer/estimation-table.js) builds the same tables as the Python reference."""

import copy
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

import pytest

import estimation_format as ef
from estimation_format import table as et
from estimation_format import views

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "schema" / "examples"
NODE = shutil.which("node")


def test_examples_js_is_current():
    spec = importlib.util.spec_from_file_location("make_examples", ROOT / "viewer" / "make_examples.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert (ROOT / "viewer" / "examples.js").read_text(encoding="utf-8") == mod.content(), (
        "run: python viewer/make_examples.py"
    )


FILES = {
    "paper.estimation-collection.json": "paper",
    "session.estimation-collection.json": "session",
    "replication.estimation-collection.json": "replication",
    "replication.members.jsonl": None,
}


def specs():
    base = et.read_table(EXAMPLES / "paper.estimation-table.json")
    out = [base]
    for unc in ("statistic", "p_value", "conf_int", None):
        s = copy.deepcopy(base)
        s["uncertainty"] = unc
        out.append(s)
    s = copy.deepcopy(base)
    s.update(
        stars=[0.05, 0.01, 0.001],
        format={"digits": 2, "thousands": " ", "fe_yes": "X", "star_symbols": ["+", "*", "**"]},
    )
    s["drop"] = []
    s["rows"] = [{"terms": ["hp", "wt"], "label": "hp or wt"}]
    out.append(s)
    coll = ef.read_collection(EXAMPLES / "session.estimation-collection.json")
    s = et.new_table(coll, stats=["nobs", "r2", "r2_within", {"vcov": "type"}, {"vcov": "n_clusters"}])
    s["columns"].append(dict(s["columns"][0], header="iid", vcov="iid"))
    s["columns"].append(dict(s["columns"][1], header="pos", vcov=1))
    for c in s["columns"]:
        c["source"] = "session"
    s["sources"] = [{"id": "session", "path": "session.estimation-collection.json"}]
    out.append(s)
    s = copy.deepcopy(s)
    s["keep"] = ["^x1$"]
    s["uncertainty"] = "conf_int"
    out.append(s)
    return out


@pytest.fixture(scope="module")
def node_result():
    if NODE is None:
        pytest.skip("node not installed")
    grid = [
        (t, df)
        for df in (1, 2.5, 5, 30, 997, 9999, 1e4, 1e6, 1e9, None)
        for t in (0, 0.3, 1, 1.96, 4, 9.5, 25)
    ]
    crit = [(lv, df) for lv in (0.9, 0.95, 0.99) for df in (1, 3, 49, 997, 1e5, None)]
    req = {
        "files": [{"name": n, "text": (EXAMPLES / n).read_text(encoding="utf-8")} for n in FILES],
        "sources": FILES,
        "specs": specs(),
        "pvals": grid,
        "crit": crit,
    }
    run = subprocess.run(
        [NODE, str(ROOT / "tests" / "viewer_check.js")],
        input=json.dumps(req),
        capture_output=True,
        text=True,
        check=False,
    )
    assert run.returncode == 0, run.stderr
    return req, json.loads(run.stdout)


def test_tables_match_python(node_result):
    _req, out = node_result
    for i, (spec, js) in enumerate(zip(specs(), out["tables"])):
        py = et.build_table(spec, base_dir=EXAMPLES)
        assert "error" not in js, (i, js)
        assert js["header"] == py["header"], i
        assert [r["label"] for r in js["rows"]] == [r["label"] for r in py["rows"]], i
        assert [r["cells"] for r in js["rows"]] == [r["cells"] for r in py["rows"]], i
        assert js["notes"] == py["notes"], i


def test_renderers_match_python(node_result):
    """Each format renders the built table the same way (the JS renderers on Python's table)."""
    if NODE is None:
        pytest.skip("node not installed")
    py = et.build_table(specs()[0], base_dir=EXAMPLES)
    script = (
        "const E=require(process.argv[1]);const t=JSON.parse(require('fs').readFileSync(0,'utf8'));"
        "process.stdout.write(JSON.stringify(Object.fromEntries(['text','markdown','latex','html','csv'].map(f=>[f,E.render(t,f)]))))"
    )
    run = subprocess.run(
        [NODE, "-e", script, str(ROOT / "viewer" / "estimation-table.js")],
        input=json.dumps(py),
        capture_output=True,
        text=True,
        check=False,
    )
    assert run.returncode == 0, run.stderr
    for fmt, text in json.loads(run.stdout).items():
        assert text == et.render(py, fmt), fmt


def test_distributions_match_python(node_result):
    req, out = node_result
    for (t, df), p in zip(req["pvals"], out["pvals"]):
        want = views.two_sided_p(t, df)
        assert p == pytest.approx(want, rel=1e-9, abs=1e-300), (t, df)
    for (lv, df), q in zip(req["crit"], out["crit"]):
        assert q == pytest.approx(views.critical_value(lv, df), rel=1e-10), (lv, df)


def test_hashes_match_python(node_result):
    _req, out = node_result
    recs = {}
    for name in ("paper", "session"):
        coll = ef.read_collection(EXAMPLES / f"{name}.estimation-collection.json")
        recs.update({r["meta"]["id"]: r for _, _, r in ef.iter_members(coll)})
    for rid, h in out["hashes"]:
        if rid in recs:
            assert h == ef.member_sha256(recs[rid]), rid


def test_missing_record_errors_in_both():
    if NODE is None:
        pytest.skip("node not installed")
    s = copy.deepcopy(specs()[0])
    s["columns"][0]["record"] = "missing"
    with pytest.raises(ValueError, match="not found"):
        et.build_table(s, base_dir=EXAMPLES)
    req = {"files": [], "sources": {}, "specs": [s], "pvals": [], "crit": []}
    run = subprocess.run(
        [NODE, str(ROOT / "tests" / "viewer_check.js")],
        input=json.dumps(req),
        capture_output=True,
        text=True,
        check=False,
    )
    assert "not found" in json.loads(run.stdout)["tables"][0]["error"]

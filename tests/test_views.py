"""Views for tables: tidy, glance, parameters_table and glance_table, and the stdlib t
distribution behind them."""

import math

import pytest

import estimation_format as ef
from estimation_format import records as est
from estimation_format import views

EXAMPLES = est.PACKAGED_SCHEMAS / "examples"


def hand_record():
    """A clustered default vcov and an iid one, two FEs, a collinear term, a structured and a
    non-finite metric, and a first-stage row (the same record as estrec's test-read.R)."""
    return {
        "schema": "estimation/0.1",
        "meta": {
            "id": "6f1c0000-0000-4000-8000-0000000000aa",
            "created": "2026-11-05T07:00:00Z",
            "status": "ok",
            "estimator": {"family": "linear", "method": "ols"},
            "responses": ["y"],
            "title": "hand-made",
        },
        "specification": {"fixed_effects": ["firm", "year"], "clusters": ["firm"]},
        "metrics": {
            "nobs": 1000,
            "r2": 0.6,
            "r2_within": {"value": 0.2, "definition": "demeaned"},
            "f_stat": math.inf,
            "rss": 100,
            "tss": 250,
            "conf_level": 0.95,
        },
        "parameters": [
            {
                "term": "x1",
                "estimate": 0.5,
                "std_error": 0.1,
                "statistic": 5,
                "p_value": 1e-6,
                "conf_low": 0.3,
                "conf_high": 0.7,
            },
            {
                "term": "x2",
                "estimate": -0.2,
                "std_error": 0.05,
                "statistic": -4,
                "p_value": 1e-4,
                "conf_low": -0.3,
                "conf_high": -0.1,
            },
            {"term": "x3", "dropped": "collinear"},
            {
                "term": "z",
                "component": "first_stage",
                "response": "x1",
                "estimate": 0.6,
                "std_error": 0.03,
                "statistic": 20,
                "p_value": 1e-80,
            },
        ],
        "structures": {
            "vcov": [
                {
                    "kind": "matrix",
                    "labels": ["x1", "x2"],
                    "data": [[0.01, 0], [0, 0.0025]],
                    "type": "CRV1",
                    "cluster": ["firm"],
                    "df_t": 49,
                    "default": True,
                },
                {
                    "kind": "matrix",
                    "labels": ["x1", "x2"],
                    "data": [[0.0004, 0], [0, 0.0001]],
                    "type": "iid",
                    "df_t": 997,
                    "default": False,
                },
            ]
        },
    }


@pytest.mark.parametrize("df", [1, 2.5, 5, 30, 997, 1e5, 1e6, 1e7, 2e7, 1e8, 1e12])
@pytest.mark.parametrize("t", [0.0, 0.3, 1.0, 1.96, 4.0, 25.0])
def test_t_distribution_matches_scipy(t, df):
    stats = pytest.importorskip("scipy.stats")
    assert views.two_sided_p(t, df) == pytest.approx(2 * stats.t.sf(t, df), rel=1e-10, abs=1e-300)
    assert views.two_sided_p(t) == pytest.approx(2 * stats.norm.sf(t), rel=1e-10, abs=1e-300)


@pytest.mark.parametrize("df", [1, 3, 49, 997])
@pytest.mark.parametrize("level", [0.9, 0.95, 0.99])
def test_critical_value_matches_scipy(level, df):
    stats = pytest.importorskip("scipy.stats")
    assert views.critical_value(level, df) == pytest.approx(stats.t.ppf(1 - (1 - level) / 2, df), rel=1e-10)
    assert views.critical_value(level) == pytest.approx(stats.norm.ppf(1 - (1 - level) / 2), rel=1e-12)


def test_tidy_as_written():
    rows = ef.tidy(hand_record())
    assert [r["term"] for r in rows] == ["x1", "x2"]
    assert [r["std_error"] for r in rows] == [0.1, 0.05]
    assert [r["conf_low"] for r in rows] == [0.3, -0.3]
    assert all("component" not in r for r in rows)
    assert [r["term"] for r in ef.tidy(hand_record(), component="first_stage")] == ["z"]
    assert len(ef.tidy(hand_record(), component="all", dropped=True)) == 4


@pytest.mark.parametrize("sel", ["iid", 1])
def test_tidy_other_vcov(sel):
    rows = ef.tidy(hand_record(), vcov=sel)
    assert [r["std_error"] for r in rows] == pytest.approx([0.02, 0.01])
    assert [r["statistic"] for r in rows] == pytest.approx([25, -20])
    q = views.critical_value(0.95, 997)
    assert rows[0]["conf_high"] == pytest.approx(0.5 + q * 0.02)
    assert rows[1]["p_value"] == pytest.approx(views.two_sided_p(20, 997))


def test_tidy_level_and_selection():
    rows = ef.tidy(hand_record(), conf_level=0.9)
    assert rows[0]["conf_low"] == pytest.approx(0.5 - views.critical_value(0.9, 49) * 0.1)
    assert ef.tidy(hand_record(), vcov="firm")[0]["std_error"] == 0.1  # the default, by cluster
    with pytest.raises(ValueError, match="no vcov 'HC3'"):
        ef.tidy(hand_record(), vcov="HC3")


def test_glance():
    g = ef.glance(hand_record())
    assert g["nobs"] == 1000 and g["r2"] == 0.6 and g["r2_within"] == 0.2
    assert math.isinf(g["f_stat"]) and "conf_level" not in g
    assert g["vcov_type"] == "by: firm" and g["fixed_effects"] == ["firm", "year"]
    assert ef.glance(hand_record(), vcov="iid")["vcov_type"] == "iid"
    assert g["rmse"] == pytest.approx(math.sqrt(0.1)) and "rss" not in g and "tss" not in g
    ga = ef.glance(hand_record(), metrics="all")
    assert ga["rss"] == 100 and ga["tss"] == 250 and "rmse" not in ga


def test_read_record_strings_decode(tmp_path):
    path = tmp_path / "hand.estimation.json"
    ef.write(hand_record(), path)
    rec = ef.read(path, nonfinite="string")  # "Inf" left as a string
    assert math.isinf(ef.glance(rec)["f_stat"])


@pytest.mark.parametrize("members", ["embed", "jsonl"])
def test_parameters_table_collection(tmp_path, members):
    a = hand_record()
    b = hand_record()
    b["meta"]["id"] = "6f1c0000-0000-4000-8000-0000000000bb"
    coll = ef.new_collection(
        {"base": a, "full": b}, kind="batch", locators=["col. 1", {"table": "2", "column": "2"}]
    )
    path = tmp_path / "t.estimation-collection.json"
    ef.write_collection(coll, path, members=members) if members == "jsonl" else ef.write_collection(
        coll, path
    )
    coll = ef.read_collection(path)
    rows = ef.parameters_table(coll, base_dir=tmp_path)
    assert [(r["member"], r["term"]) for r in rows] == [
        ("base", "x1"),
        ("base", "x2"),
        ("full", "x1"),
        ("full", "x2"),
    ]
    assert rows[0]["locator"] == "col. 1" and rows[2]["locator"] == "table 2, column 2"
    g = ef.glance_table(coll, base_dir=tmp_path)
    assert [r["member"] for r in g] == ["base", "full"] and g[1]["nobs"] == 1000


def test_parameters_table_mapping_and_list():
    rows = ef.parameters_table({"m1": hand_record()}, vcov="iid")
    assert {r["member"] for r in rows} == {"m1"} and rows[0]["std_error"] == pytest.approx(0.02)
    assert ef.parameters_table([hand_record()])[0]["member"] == "hand-made"


@pytest.mark.parametrize("path", sorted(EXAMPLES.glob("*.estimation.json")), ids=lambda p: p.name)
def test_examples(path):
    rec = ef.read(path)
    rows = ef.tidy(rec)
    assert all("term" in r for r in rows)
    ef.glance(rec)


@pytest.mark.parametrize("path", sorted(EXAMPLES.glob("*.estimation-collection.json")), ids=lambda p: p.name)
def test_example_collections(path):
    coll = ef.read_collection(path)
    rows = ef.parameters_table(coll, base_dir=path.parent)
    assert rows and all(r["member"] for r in rows)


def test_examples_iv_and_dfeols():
    iv = ef.read(EXAMPLES / "iv.estimation.json")
    assert "z" not in [r["term"] for r in ef.tidy(iv)]
    assert ef.tidy(iv, component="first_stage")
    d = ef.read(EXAMPLES / "dfeols-linear-fe.estimation.json")
    assert [r["std_error"] for r in ef.tidy(d, vcov="iid")] == pytest.approx(
        [math.sqrt(8.1e-05), math.sqrt(7.9e-05)]
    )

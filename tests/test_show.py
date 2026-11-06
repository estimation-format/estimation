"""`estimation show`: the detail view, the side-by-side table, and loading paths."""

import math

import pytest

import estimation_format as ef
from estimation_format import records as est
from estimation_format import show as sh

EXAMPLES = est.PACKAGED_SCHEMAS / "examples"


def rec(i, **metrics):
    return {
        "schema": "estimation/0.1",
        "meta": {
            "id": f"6f1c0000-0000-4000-8000-{i:012d}",
            "created": "2026-11-05T08:00:00Z",
            "status": "ok",
            "estimator": {"family": "linear", "method": "ols"},
            "responses": ["y"],
        },
        "specification": {"fixed_effects": ["firm"] if i == 2 else []},
        "metrics": {"nobs": 123456, "r2": 0.5, **metrics},
        "parameters": [
            {"term": "x", "estimate": 0.5 + i, "std_error": 0.1, "p_value": 0.003},
            *([{"term": "w", "estimate": -0.25, "std_error": 0.2, "p_value": 0.21}] if i == 2 else []),
            {"term": "z", "dropped": "collinear"},
        ],
        "structures": {
            "vcov": [
                {
                    "kind": "matrix",
                    "labels": ["x"],
                    "data": [[0.01]],
                    "type": "iid",
                    "df_t": 100,
                    "default": True,
                }
            ]
        },
        "tests": [{"label": "pre-trends", "statistic": 1.5, "distribution": "F", "p_value": 0.22}],
    }


def test_detail_view():
    text = sh.show_record(rec(1, aic=10.5))
    assert "linear / ols of y" in text and "vcov: iid" in text
    assert "nobs 123,456" in text  # counts in full
    assert "(collinear)" in text and "**" in text
    assert "test pre-trends: F = 1.500, p = 0.22" in text


def test_table_aligns_terms_and_stats():
    text = sh.show_table([("a", rec(1)), ("b", rec(2))])
    lines = text.splitlines()
    assert lines[0].split() == ["a", "b"]
    x = next(ln for ln in lines if ln.startswith("x "))
    assert x.split()[1:] == ["1.500***", "2.500***"]
    w = next(ln for ln in lines if ln.startswith("w "))
    assert w.split()[1:] == ["-0.250"]  # only in b
    assert next(ln for ln in lines if ln.startswith("N ")).split()[1:] == ["123,456", "123,456"]
    assert next(ln for ln in lines if ln.startswith("FE: firm")).split()[2:] == ["X"]
    assert "z" not in [ln.split()[0] for ln in lines if ln.strip()]  # dropped terms left out


def test_fmt():
    assert sh._fmt(1234567) == "1,234,567"
    assert sh._fmt(0.123456) == "0.123"
    assert sh._fmt(1.2e-7) == "1.20e-07"
    assert sh._fmt(math.inf) == "Inf" and sh._fmt(math.nan) == "NaN"


def test_paths_folder_collection_and_cli(tmp_path, capsys):
    for i in (1, 2):
        ef.write(rec(i), tmp_path / f"m{i}.estimation.json")
    assert [n for n, _, _ in sh.load_for_show([tmp_path])] == ["m1", "m2"]
    coll = ef.new_collection({"base": rec(1), "fe": rec(2)}, kind="batch", locators=["col. 1", "col. 2"])
    cp = tmp_path / "c.estimation-collection.json"
    ef.write_collection(coll, cp, members="jsonl")
    items = sh.load_for_show([cp])
    assert [n for n, _, _ in items] == ["base", "fe"] and items[0][2]["label"] == "base"
    assert sh.main([str(cp)]) == 0
    assert capsys.readouterr().out.splitlines()[0].split() == ["base", "fe"]
    assert sh.main([str(cp), "--detail"]) == 0
    assert "member: fe  (col. 2)" in capsys.readouterr().out
    assert sh.main([str(tmp_path / "missing.estimation.json")]) == 1


@pytest.mark.parametrize("path", sorted(EXAMPLES.glob("*.estimation.json")), ids=lambda p: p.name)
def test_examples_render(path):
    assert sh.show([path])
    assert sh.show([path], table=True)


@pytest.mark.parametrize("path", sorted(EXAMPLES.glob("*.estimation-collection.json")), ids=lambda p: p.name)
def test_example_collections_render(path):
    assert sh.show([path])


def test_show_uses_the_table_star_cuts():
    from estimation_format.table import DEFAULT_STARS

    assert sh.STARS == DEFAULT_STARS == [0.1, 0.05, 0.01]
    assert [sh._stars(p) for p in (0.2, 0.07, 0.03, 0.005, None)] == ["", "*", "**", "***", ""]
    text = sh.show_table([("a", rec(1))])
    assert text.splitlines()[-1] == "* p < 0.1, ** p < 0.05, *** p < 0.01"

"""Disclosure levels and purpose profiles (spec 4.9 and 9.1): the schema's x-level marks,
writing at a level, lowering a record, the validator's checks, and purpose profiles."""

import copy
import json
import warnings

import pytest
from test_estimation import fe_record, lm_record

from estimation_format import records as est


def errors(issues):
    return [i for i in issues if i.level == "error"]


def warns(issues):
    return [i for i in issues if i.level == "warning"]


# ---------------------------------------------------------------- the marks


def test_builtin_marks_match_the_core_schema():
    sc = est.load_schemas()
    assert est.level_marks(sc.core, sc.documents()) == est.DEFAULT_LEVEL_MARKS


def test_marks_never_go_below_an_enclosing_mark():
    """A field is never more disclosable than what contains it, so removing a field above a
    level never removes something at or below it."""
    marks = est.DEFAULT_LEVEL_MARKS
    for path, (lvl, conds) in marks.items():
        parts = est._split(path)
        for i in range(1, len(parts)):
            outer = marks.get(".".join(parts[:i]).replace(".[*]", "[*]"))
            if outer and outer[0] is not None:
                lowest = min([outer[0], *(c[2] for c in outer[1])])  # its x-level-if can lower it
                assert lvl >= lowest, (path, lvl, outer)
                assert all(c[2] >= lowest for c in conds), path


def test_every_top_level_member_is_marked():
    for k in (*est.REQUIRED, *est.EXPECTED, *est.OPTIONAL):
        assert k in est.DEFAULT_LEVEL_MARKS, k


# ---------------------------------------------------------------- writing at a level


def test_level_1_is_results_only_and_valid_without_warnings():
    rec = est.prepare(lm_record(), level=1)
    assert set(rec) == {"schema", "meta", "parameters", "metrics", "history"}
    assert rec["metrics"] == {"nobs": 32, "df_residual": 30, "conf_level": 0.95}
    assert set(rec["meta"]) == {"id", "created", "status", "disclosure", "core_digest"}
    assert rec["meta"]["disclosure"] == {"level": 1}
    assert rec["meta"]["created"] == "2026-10-24T15:02:11Z"  # given by the caller: kept
    assert {k for row in rec["parameters"] for k in row} == {
        "term",
        "estimate",
        "std_error",
        "statistic",
        "p_value",
    }
    h = rec["history"][-1]
    assert set(h) == {"when", "action", "level"} and len(h["when"]) == 10  # a date
    issues = est.validate(rec)
    assert errors(issues) == [] and warns(issues) == []
    assert any("withheld at disclosure level 1" in i.message for i in issues)
    assert est.check_digest(rec) is True


def test_level_1_created_is_a_date_when_the_writer_fills_it():
    r = lm_record()
    del r["meta"]["created"]
    assert len(est.prepare(r, level=1)["meta"]["created"]) == 10
    assert len(est.prepare(r, level=2)["meta"]["created"]) > 10


def test_level_2_adds_diagnostics_and_the_vcov_without_its_clusters():
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        rec = est.prepare(fe_record(), level=2)
    assert "r2_within" in rec["metrics"] and "n_singletons" in rec["metrics"]
    v = rec["structures"]["vcov"]
    assert len(v) == 2 and all("cluster" not in s for s in v)
    assert "fixed_effects" not in rec["structures"] and "specification" not in rec
    # linear-fe and dfeols need the FE counts (level 3): not claimed, and said so
    assert "profiles" not in rec["meta"]
    codes = [m["code"] for m in rec["meta"]["messages"]]
    assert codes == ["profile_not_claimed", "profile_not_claimed"]
    assert any("linear-fe/0.1" in str(x.message) for x in w)
    assert errors(est.validate(rec)) == []


def test_a_profile_the_level_still_meets_stays_claimed():
    rec = est.prepare(lm_record(), level=2)
    assert rec["meta"]["profiles"] == ["inference/0.1"]
    assert errors(est.validate(rec)) == []


def test_level_3_keeps_profiles_that_need_the_specification():
    with pytest.warns(UserWarning, match="dfeols/0.1"):  # needs extensions.dfeols, level 4
        rec = est.prepare(fe_record(), level=3)
    assert rec["meta"]["profiles"] == ["linear-fe/0.1"]
    assert rec["structures"]["vcov"][1]["cluster"] == ["pitcher"]
    assert "provenance" not in rec and "extensions" not in rec


def test_default_level_4_lists_only_language_estimator_and_writer():
    r = lm_record()
    r["provenance"]["software"] += [
        {"name": "estrec", "version": "0.1", "role": "writer"},
        {"name": "Matrix", "version": "1.7", "role": "dependency"},
    ]
    rec = est.prepare(r)
    assert rec["meta"]["disclosure"] == {"level": 4}
    prov = rec["provenance"]
    assert [s["name"] for s in prov["software"]] == ["R", "stats", "estrec"]
    assert set(prov) == {"software", "data"} and "location" not in prov["data"][0]
    assert prov["data"][0]["checksum"]["value"] == "ab" * 32
    assert rec["history"][-1]["by"]["name"] == "estimation-format"  # the writer, traceable
    issues = est.validate(rec)
    assert errors(issues) == [] and warns(issues) == []


def test_level_5_keeps_everything():
    r = lm_record()
    rec = est.prepare(r, level=5)
    assert rec["provenance"] == r["provenance"]
    assert rec["history"][-1]["by"]["name"] == "estimation-format"
    assert errors(est.validate(rec)) == []


def test_a_record_declared_lower_keeps_its_level():
    low = est.prepare(lm_record(), level=2)
    again = est.prepare(low, level=5)
    assert again["meta"]["disclosure"] == {"level": 2}


def test_bad_level():
    with pytest.raises(est.EstimationError, match="1-5"):
        est.prepare(lm_record(), level=6)


def test_write_takes_a_level(tmp_path):
    p = tmp_path / "a.estimation.json"
    est.write(lm_record(), p, level=1)
    back = est.read(p)
    assert back["meta"]["disclosure"] == {"level": 1} and "provenance" not in back


# ---------------------------------------------------------------- the validator


def test_a_field_above_the_declared_level_is_an_error():
    rec = est.prepare(lm_record())  # level 4
    rec["provenance"]["agent"] = {"user": "ted"}
    rec["provenance"]["software"].append({"name": "Matrix", "role": "dependency"})
    found = errors(est.validate(rec))
    assert {i.path for i in found} == {"provenance.agent", "provenance.software[2]"}
    assert all("declared at disclosure level 4" in i.message for i in found)


def test_bad_declaration():
    rec = est.prepare(lm_record())
    rec["meta"]["disclosure"] = {"level": 9}
    assert {i.path for i in errors(est.validate(rec))} == {"meta.disclosure.level"}


def test_no_declaration_means_no_level_checks():
    rec = est.prepare(lm_record(), level=5)
    del rec["meta"]["disclosure"]
    est.add_digest(rec)
    assert errors(est.validate(rec)) == []


def test_record_level_and_fields_above():
    rec = est.prepare(lm_record(), level=5)
    assert est.record_level(rec) == 5
    assert est.fields_above(rec, 3) == ["provenance", "history[0].by"]
    assert est.record_level(est.prepare(lm_record(), level=1)) == 1


# ---------------------------------------------------------------- lowering


def test_reduce_writes_a_new_record_pointing_at_the_original():
    full = est.prepare(lm_record(), level=5)
    low = est.reduce(full, 1)
    assert low["meta"]["parent"] == full["meta"]["id"] and low["meta"]["id"] != full["meta"]["id"]
    assert low["meta"]["disclosure"] == {"level": 1}
    h = low["history"][-1]
    assert h["action"] == "reduced" and h["level"] == 1 and "by" not in h
    assert "provenance" in h["fields"] and "specification" in h["fields"]
    assert est.check_digest(low) is True
    issues = est.validate(low)
    assert errors(issues) == [] and warns(issues) == []
    assert "provenance" in full  # input unchanged


def test_reduce_to_the_same_level_is_a_copy():
    rec = est.prepare(lm_record(), level=2)
    out = est.reduce(rec, 3)
    assert out == rec and out is not rec


def test_reduce_drops_attachments_of_removed_structures(tmp_path):
    rec = fe_record()
    rec["structures"]["big"] = {"kind": "link", "attachment": "big"}
    rec["attachments"] = [
        {"id": "big", "path": "big.parquet", "sha256": "0" * 64},
        {"id": "fe", "path": "fe.parquet", "sha256": "1" * 64},
    ]
    out = est.reduce(est.prepare(rec, level=5), 2)
    assert [a["id"] for a in out["attachments"]] == ["fe"]  # nothing linked to it: kept


# ---------------------------------------------------------------- tests and redaction


def test_add_test_respects_the_level():
    low = est.prepare(lm_record(), level=1)
    with pytest.raises(est.EstimationError, match="level 2"):
        est.add_test(low, {"name": "wald", "statistic": 1.0, "distribution": "F", "df1": 1, "df2": 30})
    rec = est.prepare(lm_record(), level=2)
    est.add_test(
        rec,
        {
            "name": "wald",
            "statistic": 1.0,
            "distribution": "F",
            "df1": 1,
            "df2": 30,
            "source": {"name": "car", "version": "3.1"},
        },
    )
    assert "source" not in rec["tests"][-1] and "by" not in rec["history"][-1]
    assert errors(est.validate(rec)) == []


def test_redaction_names_the_redactor_from_level_4():
    out = est.redact(est.prepare(lm_record()))
    assert out["history"][-1]["action"] == "redacted" and "by" in out["history"][-1]
    assert errors(est.validate(out)) == []
    low = est.redact(est.prepare(lm_record(), level=3))
    assert "by" not in low["history"][-1] and errors(est.validate(low)) == []


# ---------------------------------------------------------------- purpose profiles


@pytest.fixture
def purpose_schemas(tmp_path):
    """A local purpose profile: level 3, and the formula as written."""
    doc = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://example.org/share-formula-0.1.json",
        "title": "share-formula/0.1",
        "x-license": "CC0-1.0",
        "x-min-level": 3,
        "allOf": [
            {"$ref": "https://estimation-format.github.io/estimation/schema/estimation-0.1.json"},
            {"$ref": "#/$defs/rules"},
        ],
        "$defs": {
            "rules": {
                "type": "object",
                "required": ["specification"],
                "properties": {"specification": {"type": "object", "required": ["formula"]}},
            }
        },
    }
    (tmp_path / "share-formula-0.1.json").write_text(json.dumps(doc))
    pytest.importorskip("jsonschema")
    return est.load_schemas([tmp_path])


def test_purpose_sets_the_level_and_is_claimed(purpose_schemas):
    rec = est.prepare(lm_record(), purpose="share-formula/0.1", schema=purpose_schemas)
    assert rec["meta"]["disclosure"] == {"level": 3}
    assert rec["meta"]["profiles"] == ["inference/0.1", "share-formula/0.1"]
    assert "provenance" not in rec and rec["specification"]["formula"]["text"] == "mpg ~ wt"
    assert errors(est.validate(rec, schema=purpose_schemas)) == []


def test_purpose_above_the_level_fails_early(purpose_schemas):
    with pytest.raises(est.EstimationError, match="below the 3"):
        est.prepare(lm_record(), level=2, purpose="share-formula/0.1", schema=purpose_schemas)


def test_purpose_the_record_falls_short_of(purpose_schemas):
    r = lm_record()
    del r["specification"]["formula"]
    with pytest.raises(est.EstimationError, match="formula"):
        est.prepare(r, purpose="share-formula/0.1", schema=purpose_schemas)


def test_only_purpose_profiles_are_purposes(purpose_schemas):
    with pytest.raises(est.EstimationError, match="not a purpose profile"):
        est.prepare(lm_record(), purpose="inference/0.1", schema=purpose_schemas)
    with pytest.raises(est.EstimationError, match="no such profile"):
        est.prepare(lm_record(), purpose="nope/0.1", schema=purpose_schemas)


def test_validator_flags_a_purpose_above_the_declared_level(purpose_schemas):
    rec = est.prepare(lm_record(), purpose="share-formula/0.1", schema=purpose_schemas)
    rec = copy.deepcopy(rec)
    rec["meta"]["disclosure"] = {"level": 2}
    del rec["specification"]
    est.add_digest(rec)
    found = [
        i for i in errors(est.validate(rec, schema=purpose_schemas)) if i.path == "meta.disclosure.level"
    ]
    assert found and "needs disclosure level 3" in found[0].message


# ---------------------------------------------------------------- aea/0.1


def aea_record():
    return est.read(est.PACKAGED_SCHEMAS / "examples" / "aea.estimation.json", nonfinite="string")


def aea_errors(rec):
    est.add_digest(rec)
    return {i.path for i in errors(est.validate(rec)) if "[aea/0.1]" in i.message}


def test_aea_is_a_level_4_purpose():
    sc = est.load_schemas()
    assert est.is_purpose("aea/0.1", sc) and est.min_level("aea/0.1", sc) == 4
    with pytest.raises(est.EstimationError, match="below the 4"):
        est.prepare(aea_record(), level=3, purpose="aea/0.1")


def test_aea_example_meets_it_without_warnings():
    pytest.importorskip("jsonschema")
    issues = est.validate(aea_record())
    assert errors(issues) == [] and warns(issues) == []


@pytest.mark.parametrize(
    "edit, path",
    [
        (lambda r: r["publication"]["locator"].pop("label"), "publication.locator.label"),
        (lambda r: r["publication"]["locator"].pop("table"), "publication.locator"),
        (lambda r: r["provenance"].pop("data"), "provenance.data"),
        (lambda r: r["provenance"]["data"][0].pop("name"), "provenance.data[0].name"),
        (lambda r: r["provenance"]["software"][0].pop("version"), "provenance.software"),
        # an interval stands in for a standard error; with neither, the row fails
        (lambda r: [r["parameters"][0].pop(k) for k in ("std_error", "conf_low")], "parameters[0]"),
    ],
)
def test_aea_requirements(edit, path):
    pytest.importorskip("jsonschema")
    rec = aea_record()
    edit(rec)
    assert path in aea_errors(rec)


def test_aea_expects_the_program_and_data_citation():
    pytest.importorskip("jsonschema")
    rec = aea_record()
    del rec["specification"]["program"]
    del rec["provenance"]["data"][0]["publication"]
    est.add_digest(rec)
    found = {i.path for i in warns(est.validate(rec))}
    assert found == {"specification.program", "provenance.data[0].publication"}


def test_aea_needs_a_seed_for_resampling():
    pytest.importorskip("jsonschema")
    rec = aea_record()
    rec["meta"]["profiles"].append("resampling/0.1")
    rec["specification"]["resampling"] = {"method": "wild_cluster", "reps": 999, "seed": None}
    assert "specification.resampling.seed" in aea_errors(rec)
    rec["specification"]["resampling"]["seed"] = 20261105
    assert not {p for p in aea_errors(rec) if "seed" in p}

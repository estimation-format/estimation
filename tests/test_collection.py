"""Collections (spec section 11): building, writing (embedded and members files), reading,
validating, redacting, and the command line."""

import copy
import json
import math
from pathlib import Path

import pytest

import estimation_format as ef
from estimation_format import collection as col
from estimation_format import records as est

EXAMPLES = est.PACKAGED_SCHEMAS / "examples"
SCHEMAS = ["auto", None]  # with the JSON Schemas (when jsonschema is installed) and without


def record(i, **extra):
    """A small valid record with a fixed id."""
    rec = {
        "schema": "estimation/0.1",
        "meta": {
            "id": f"6f1c0000-0000-4000-8000-{i:012d}",
            "created": f"2026-11-01T10:00:0{i}Z",
            "status": "ok",
        },
        "specification": {"call": f"lm(y ~ x{i})"},
        "metrics": {"nobs": 32, "sigma": math.nan},
        "parameters": [{"term": "x", "estimate": 0.5 + i, "std_error": 0.1, "statistic": math.inf}],
        "provenance": {"agent": {"user": "ada", "host": "valiant"}},
    }
    for k, v in extra.items():
        rec[k] = v
    return rec


def paper(**kw):
    return ef.new_collection(
        {"col1": record(1), "col2": record(2)},
        kind="paper",
        locators=["Table 1, col. (1)", {"table": "1", "column": "2"}],
        publication={"citation": {"type": "report", "title": "A paper", "DOI": "10.0000/X"}},
        **kw,
    )


def messages(issues, level=None):
    return [f"{i.path}: {i.message}" for i in issues if level is None or i.level == level]


# ---------------------------------------------------------------- building


def test_new_collection_members():
    c = paper(title="Table 1")
    assert c["schema"] == "estimation-collection/0.1"
    assert c["meta"]["kind"] == "paper" and c["meta"]["title"] == "Table 1"
    m1, m2 = c["members"]
    assert m1["id"] == m1["record"]["meta"]["id"] and m1["label"] == "col1"
    assert m1["created"] == "2026-11-01T10:00:01Z"
    assert m1["locator"] == {"label": "Table 1, col. (1)"} and m2["locator"] == {"table": "1", "column": "2"}
    assert m1["sha256"] == ef.member_sha256(record(1))
    assert m1["record"]["metrics"]["sigma"] == "NaN"  # encoded as written
    # several locators, none, and no hash
    c = ef.new_collection([record(1), record(2)], kind="batch", locators=[["T1", "T5"], None], sha256=False)
    assert c["members"][0]["locators"] == [{"label": "T1"}, {"label": "T5"}]
    assert "locator" not in c["members"][1] and "sha256" not in c["members"][0]


def test_new_collection_refuses():
    with pytest.raises(est.EstimationError, match="kind"):
        ef.new_collection([], kind="table")
    with pytest.raises(est.EstimationError, match="more than once"):
        ef.new_collection([record(1), record(1)], kind="paper")
    with pytest.raises(est.EstimationError, match="meta.id"):
        ef.new_collection([{"schema": "estimation/0.1", "meta": {}}], kind="batch")
    with pytest.raises(est.EstimationError, match="one entry per record"):
        ef.new_collection([record(1)], kind="batch", labels=["a", "b"])


def test_member_sha256_is_over_the_record_as_written():
    r = record(1)
    h = ef.member_sha256(r)
    assert h == ef.member_sha256(json.loads(json.dumps(est.to_json(r))))  # "NaN" strings
    assert h == ef.member_sha256(est.decode_nonfinite(est.to_json(r)))  # floats again
    assert h != ef.member_sha256(est.add_test(copy.deepcopy(r), {"name": "wald", "statistic": 1.0}))


# ---------------------------------------------------------------- writing and reading


def test_write_and_read_embedded(tmp_path):
    p = tmp_path / "t1.estimation-collection.json"
    written = ef.write_collection(paper(), p)
    assert list(written)[:3] == ["schema", "meta", "publication"]
    assert written["history"][-1]["action"] == "created"
    back = ef.read_collection(p)
    assert math.isnan(back["members"][0]["record"]["metrics"]["sigma"])
    assert ef.read_collection(p, nonfinite="string")["members"][0]["record"]["metrics"]["sigma"] == "NaN"
    assert messages(ef.validate_collection(back, base_dir=tmp_path), "error") == []
    assert [p.name] == [f.name for f in tmp_path.iterdir()]  # no members file


def test_write_members_file(tmp_path):
    p = tmp_path / "t1.estimation-collection.json"
    written = ef.write_collection(paper(), p, members="jsonl")
    f = tmp_path / "t1.members.jsonl"
    lines = f.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 2 and json.loads(lines[0])["meta"]["id"] == written["members"][0]["id"]
    (att,) = written["attachments"]
    assert att["role"] == "members" and att["media_type"] == "application/jsonl" and att["rows"] == 2
    assert att["path"] == f.name and att["sha256"] == est._sha256_file(f)
    assert all(m["attachment"] == att["id"] and "record" not in m for m in written["members"])
    # hashes are the same however the member is stored
    assert [m["sha256"] for m in written["members"]] == [m["sha256"] for m in paper()["members"]]
    coll = ef.read_collection(p)
    assert [r["meta"]["id"] for _, _, r in ef.iter_members(coll, tmp_path)] == [
        m["id"] for m in coll["members"]
    ]
    emb = ef.read_collection(p, embed=True)
    assert "attachments" not in emb and emb["members"][1]["record"]["parameters"][0]["statistic"] == math.inf
    # written again, embedded, from the members file
    q = tmp_path / "t2.estimation-collection.json"
    again = ef.write_collection(coll, q, members="embed", source_dir=tmp_path)
    assert (
        "attachments" not in again and again["members"][0]["record"]["meta"]["id"] == coll["members"][0]["id"]
    )


def test_auto_switches_to_a_members_file_above_the_limit(tmp_path, monkeypatch):
    monkeypatch.setattr(col, "FAIL_BYTES", 2_000)
    p = tmp_path / "big.estimation-collection.json"
    written = ef.write_collection(paper(), p)
    assert written["attachments"][0]["role"] == "members"
    assert (tmp_path / "big.members.jsonl").is_file()


def test_reading_a_record_is_refused():
    with pytest.raises(est.EstimationError, match="not an estimation-collection"):
        ef.loads_collection(json.dumps(est.to_json(record(1))))


# ---------------------------------------------------------------- validator


@pytest.mark.parametrize("schema", SCHEMAS)
def test_examples_are_valid(schema):
    for name in ("paper", "session", "replication"):
        coll = ef.read_collection(EXAMPLES / f"{name}.estimation-collection.json")
        issues = ef.validate_collection(coll, schema=schema, base_dir=EXAMPLES)
        own = [m for m in messages(issues) if ".record" not in m and not m.startswith(": ")]
        assert messages(issues, "error") == [] and own == [], name
    # the replication's records come from its members file and are checked
    rep = ef.read_collection(EXAMPLES / "replication.estimation-collection.json")
    assert [r is not None for _, _, r in ef.iter_members(rep, EXAMPLES)] == [True, True]


@pytest.mark.parametrize("schema", SCHEMAS)
def test_structural_errors(schema):
    c = paper()
    c["members"].append({"id": "x"})  # neither record nor attachment
    c["members"].append({"id": "y", "attachment": "nope"})
    c["members"].append(copy.deepcopy(c["members"][0]))  # id used twice
    c["meta"].pop("kind")
    errs = messages(ef.validate_collection(c, schema=schema), "error")
    assert any(e.startswith("members[2]") for e in errs)
    assert any("no attachment with id 'nope'" in e for e in errs)
    assert any("duplicate id" in e for e in errs)
    assert any(e.startswith("meta.kind") or "'kind' is a required" in e for e in errs)


@pytest.mark.parametrize("schema", SCHEMAS)
def test_member_checks(schema):
    c = paper()
    c["members"][0]["id"] = "6f1c0000-0000-4000-8000-999999999999"  # not the record's
    c["members"][1]["sha256"] = "0" * 64
    issues = ef.validate_collection(c, schema=schema)
    assert any("record's meta.id" in m for m in messages(issues, "error"))
    assert "members[1].sha256: does not match the record: the collection holds another version" in messages(
        issues, "warning"
    )
    # no sha256 at all: nothing to report
    c = paper(sha256=False)
    assert not [m for m in messages(ef.validate_collection(c, schema=schema)) if "sha256" in m]


@pytest.mark.parametrize("schema", SCHEMAS)
def test_member_records_are_validated_as_records(schema):
    bad = record(1)
    del bad["parameters"]
    c = ef.new_collection([bad], kind="batch")
    errs = messages(ef.validate_collection(c, schema=schema), "error")
    assert any(e.startswith(("members[0].record.parameters", "members[0].record:")) for e in errs)


@pytest.mark.parametrize("schema", SCHEMAS)
def test_locator_and_citation_checks(schema):
    r1 = record(
        1,
        publication={
            "locator": {"table": "1", "column": "1", "label": "T1 c1"},
            "citation": {"type": "report", "DOI": "10.0000/other"},
        },
    )
    r2 = record(2, publication={"locators": [{"table": 1, "column": 2}, {"table": "A1", "column": "1"}]})
    c = ef.new_collection(
        [r1, r2],
        kind="paper",
        locators=[{"table": "1", "column": "1"}, {"table": "1", "column": "2", "label": "as printed"}],
        publication={"citation": {"type": "report", "DOI": "10.0000/X"}},
    )
    warns = messages(ef.validate_collection(c, schema=schema), "warning")
    assert not [w for w in warns if "locator" in w]  # labels aside, 1 == "1"
    assert any("10.0000/other differs from the collection's 10.0000/x" in w for w in warns)
    c["members"][1]["locator"] = {"table": "2", "column": "2"}
    warns = messages(ef.validate_collection(c, schema=schema), "warning")
    assert "members[1].locator: matches none of the record's publication locators" in warns


@pytest.mark.parametrize("schema", SCHEMAS)
def test_kind_expectations(schema):
    c = ef.new_collection([record(1)], kind="paper")
    warns = messages(ef.validate_collection(c, schema=schema), "warning")
    assert "publication.citation: [paper] expected, missing" in warns
    assert "members[0]: [paper] expected a locator, none present" in warns
    assert "members: [paper] expected at least one member" in messages(
        ef.validate_collection(ef.new_collection([], kind="paper"), schema=schema), "warning"
    )

    r1 = record(1)
    r1["provenance"]["execution"] = {"session": "s1"}
    r2 = record(2)
    r2["provenance"]["execution"] = {"session": "other"}
    c = ef.new_collection([r1, r2, record(3)], kind="session", session={"id": "s1"})
    warns = messages(ef.validate_collection(c, schema=schema), "warning")
    assert "events: [session] expected, missing" in warns
    assert any("members[1].record.provenance.execution.session: [session] is 'other'" in w for w in warns)
    assert "members[2].record.provenance.execution.session: [session] missing" in warns
    ef.add_event(c, "fit", member=r1["meta"]["id"], when="2026-11-01T10:00:00Z")
    ef.add_event(c, "note", when="2026-11-01T09:00:00Z")
    ef.add_event(c, "fit", member="no-such-member", when="2026-11-01T11:00:00Z")
    issues = ef.validate_collection(c, schema=schema)
    assert "events[2].member: no member with id 'no-such-member'" in messages(issues, "error")
    warns = messages(issues, "warning")
    assert "events[1].when: earlier than the event before: events are in time order" in warns
    assert "members[1]: [session] expected a fit event for this member, none present" in warns
    assert "members[0]: [session] expected a fit event for this member, none present" not in warns
    # a session collection must say which session
    del c["session"]
    assert any("session" in e for e in messages(ef.validate_collection(c, schema=schema), "error"))

    c = ef.new_collection([record(1)], kind="replication")
    warns = messages(ef.validate_collection(c, schema=schema), "warning")
    assert {"events: [replication] expected, missing", "publication: [replication] expected, missing"} <= set(
        warns
    )


@pytest.mark.parametrize("schema", SCHEMAS)
def test_members_file_checks(tmp_path, schema):
    p = tmp_path / "m.estimation-collection.json"
    ef.write_collection(paper(), p, members="jsonl")
    coll = ef.read_collection(p, nonfinite="string")
    infos = messages(ef.validate_collection(coll, schema=schema), "info")
    assert any("members file not read" in m for m in infos)
    f = tmp_path / "m.members.jsonl"
    lines = f.read_text(encoding="utf-8").splitlines()
    f.write_text(lines[0] + "\n", encoding="utf-8")  # one record gone, hash broken
    warns = messages(ef.validate_collection(coll, schema=schema, base_dir=tmp_path), "warning")
    assert "attachments.members: members file does not match its sha256" in warns
    assert any(w.startswith("members[1]: record") and "not in members file" in w for w in warns)
    f.unlink()
    infos = messages(ef.validate_collection(coll, schema=schema, base_dir=tmp_path), "info")
    assert any("members file not found" in m for m in infos)


def test_size_limits_leave_out_the_records(monkeypatch):
    big = record(1, structures={"vcov": {"kind": "matrix", "data": [[0.0] * 120] * 120}})
    c = ef.new_collection([big], kind="batch")
    issues = ef.validate_collection(c, schema=None)
    # the member's own array is reported under the member, not as the collection's
    assert any(i.path.startswith("members[0].record.structures") for i in issues if i.level == "warning")
    assert not [
        i
        for i in issues
        if i.path.startswith("members") and "elements" in i.message and ".record" not in i.path
    ]
    monkeypatch.setattr(col, "FAIL_BYTES", 1_000)
    assert any("byte limit" in m for m in messages(ef.validate_collection(c, schema=None), "error"))


# ---------------------------------------------------------------- redaction


def test_identifying_paths_match_the_schema():
    pytest.importorskip("jsonschema")
    sc = est.load_schemas()
    assert set(col.collection_identifying_paths(sc)) == set(col.COLLECTION_IDENTIFYING)


@pytest.mark.parametrize("schema", SCHEMAS)
def test_redact_collection(tmp_path, schema):
    c = paper()
    c["session"] = {"id": "s1", "clients": [{"language": "R", "host": "laptop"}]}
    c["provenance"] = {"agent": {"user": "ada", "host": "valiant"}, "environment": {"hostname": "valiant"}}
    p = tmp_path / "r.estimation-collection.json"
    ef.write_collection(c, p, members="jsonl")
    coll = ef.read_collection(p, nonfinite="string")
    out = ef.redact_collection(coll, base_dir=tmp_path, schema=schema)
    assert "agent" not in out["provenance"] and "hostname" not in out["provenance"]["environment"]
    assert "host" not in out["session"]["clients"][0]
    assert out["history"][-1]["action"] == "redacted"
    for m in out["members"]:
        assert "agent" not in m["record"]["provenance"]
        assert m["record"]["history"][-1]["action"] == "redacted"
        assert m["sha256"] == ef.member_sha256(m["record"])  # refreshed
        assert m["record"]["meta"] == next(x for x in c["members"] if x["id"] == m["id"])["record"]["meta"]
    assert "attachments" not in out  # members come back embedded
    assert messages(ef.validate_collection(out, schema=schema), "error") == []
    # hashing with one salt keeps collections comparable
    a = ef.redact_collection(paper(), salt="s", schema=schema)
    b = ef.redact_collection(paper(), salt="s", schema=schema)
    assert a["members"][0]["record"]["provenance"]["agent"].startswith("hmac-sha256:")
    assert a["members"][0]["record"]["provenance"] == b["members"][0]["record"]["provenance"]
    with pytest.raises(est.EstimationError, match="not found"):
        ef.redact_collection(coll)  # the members file needs base_dir


# ---------------------------------------------------------------- command line


def test_cli(tmp_path, capsys):
    p = tmp_path / "c.estimation-collection.json"
    ef.write_collection(paper(), p, members="jsonl")
    assert est.main(["validate", str(p)]) == 0
    assert "valid (0 errors)" in capsys.readouterr().out
    assert est.main(["digest", str(p)]) == 0
    out = capsys.readouterr().out
    assert out.count("sha256") == 2 and "DOES NOT MATCH" not in out
    o = tmp_path / "shared.estimation-collection.json"
    assert est.main(["redact", str(p), "-o", str(o)]) == 0
    assert "collection and 2 member records removed" in capsys.readouterr().out
    shared = ef.read_collection(o)
    assert all("agent" not in m["record"]["provenance"] for m in shared["members"])
    bad = json.loads(p.read_text(encoding="utf-8"))
    bad["members"][0]["sha256"] = "0" * 64
    q = tmp_path / "bad.estimation-collection.json"
    q.write_text(json.dumps(bad), encoding="utf-8")
    (tmp_path / "c.members.jsonl").rename(tmp_path / "keep.jsonl")
    assert est.main(["digest", str(q)]) == 0  # members file missing: records not found, nothing compared
    assert "record not found" in capsys.readouterr().out
    (tmp_path / "keep.jsonl").rename(tmp_path / "c.members.jsonl")
    bad["attachments"][0]["path"] = "c.members.jsonl"
    q.write_text(json.dumps(bad), encoding="utf-8")
    assert est.main(["digest", str(q)]) == 1


def test_records_still_validate_through_the_cli(tmp_path, capsys):
    p = tmp_path / "r.estimation.json"
    ef.write(record(1), p)
    assert est.main(["validate", str(p)]) == 0
    assert Path(p).is_file() and "valid" in capsys.readouterr().out

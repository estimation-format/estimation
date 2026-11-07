"""The estrec JSON Schemas in schema/: the specification's examples validate, the profiles
enforce the decided required sets, and the `x-identifying` marks match what the library
redacts."""

import copy
import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "schema"
DOC = ROOT / "spec" / "estrec.md"
CORE = "estrec-0.1.json"
PROFILES = {
    "inference/0.1": "profiles/inference-0.1.json",
    "linear-fe/0.1": "profiles/linear-fe-0.1.json",
    "iv/0.1": "profiles/iv-0.1.json",
    "dfeols/0.1": "profiles/dfeols-0.1.json",
}


def load(rel):
    return json.loads((SCHEMA_DIR / rel).read_text(encoding="utf-8"))


def example(name):
    return json.loads((SCHEMA_DIR / "examples" / name).read_text(encoding="utf-8"))


def all_schemas():
    return [load(CORE), *(load(p) for p in PROFILES.values())]


# ---------------------------------------------------------------- validator (needs jsonschema)


def validator(rel, fragment=None):
    """A Draft 2020-12 validator for schema file `rel` (or `#/$defs/<fragment>` of it), with
    every schema in schema/ resolvable offline by its $id."""
    jsonschema = pytest.importorskip("jsonschema")
    root = load(rel)
    schema = {"$ref": f"{root['$id']}#/$defs/{fragment}"} if fragment else root
    try:
        from referencing import Registry, Resource

        registry = Registry().with_resources((s["$id"], Resource.from_contents(s)) for s in all_schemas())
        return jsonschema.Draft202012Validator(schema, registry=registry)
    except ImportError:  # jsonschema < 4.18
        store = {s["$id"]: s for s in all_schemas()}
        resolver = jsonschema.RefResolver(root["$id"], root, store=store)
        return jsonschema.Draft202012Validator(schema, resolver=resolver)


def errors(rel, instance, fragment=None):
    return [
        f"{'/'.join(map(str, e.absolute_path))}: {e.message}"
        for e in validator(rel, fragment).iter_errors(instance)
    ]


def profile_errors(record):
    """Errors from the core plus every profile the record claims."""
    out = errors(CORE, record)
    for p in record["meta"].get("profiles", []):
        out += [f"[{p}] {e}" for e in errors(PROFILES[p], record)]
    return out


def test_schemas_are_valid_2020_12():
    jsonschema = pytest.importorskip("jsonschema")
    for s in all_schemas():
        jsonschema.Draft202012Validator.check_schema(s)


# ---------------------------------------------------------------- the design doc's examples


def doc_blocks():
    """The ```json blocks of the specification, with `...` placeholders filled so they parse."""
    out = []
    for m in re.finditer(r"```json\n(.*?)```", DOC.read_text(encoding="utf-8"), re.DOTALL):
        s = m.group(1).replace('"by": {...}', '"by": {"name": "tool"}')
        s = s.replace("[...]", "[1.0]").replace("{...}", "{}")
        s = s.replace('"sha256": "..."', '"sha256": "' + "0" * 64 + '"')
        s = re.sub(r",\s*\.\.\.\s*}", "}", s)  # trailing "..." in an object
        s = re.sub(r":\s*\.\.\.", ": 0", s)  # "..." as a value
        s = s.strip()
        if s.startswith('"'):  # a fragment of keys: wrap it
            s = "{" + s + "}"
        dec, pos, objs = json.JSONDecoder(), 0, []
        while pos < len(s):
            o, pos = dec.raw_decode(s, pos)
            objs.append(o)
            while pos < len(s) and s[pos].isspace():
                pos += 1
        out.append(objs)
    return out


def block_kind(b):
    """A block's first key; a collection (spec 11) is "collection", not "schema"."""
    first = b[0]
    return (
        "collection" if str(first.get("schema", "")).startswith("estrec-collection/") else next(iter(first))
    )


def doc_examples():
    """The spec's JSON blocks by the first key of their first object."""
    return {block_kind(b): b for b in doc_blocks()}


def test_doc_blocks_found():
    kinds = [block_kind(b) for b in doc_blocks()]
    assert sorted(kinds) == sorted(
        ["term", "vcov", "tests", "publication", "comparisons", "id", "extensions", "schema", "collection"]
    )


def test_doc_examples_validate():
    ex = doc_examples()
    canon, vcov, pub, comp = ex["term"], ex["vcov"], ex["publication"], ex["comparisons"]
    att, ext, record = ex["id"], ex["extensions"], ex["schema"]
    for row in canon:
        assert errors(CORE, row, "parameter") == []
    assert errors(CORE, vcov[0], "structures") == []
    for t in ex["tests"][0]["tests"]:
        assert errors(CORE, t, "test") == []
    assert errors(CORE, pub[0]["publication"], "publication") == []
    assert errors(CORE, comp[0], "validation") == []
    assert errors(CORE, att[0], "attachment") == []
    assert errors(CORE, ext[0]["extensions"]["harness"], "extension") == []
    assert errors(PROFILES["dfeols/0.1"], ext[0]["extensions"]["dfeols"], "extension") == []
    assert profile_errors(record[0]) == []
    # the collection's own structure (its member records are elided in the spec)
    assert errors("estrec-collection-0.1.json", ex["collection"][0]) == []


def test_doc_lm_example_matches_file():
    record = doc_examples()["schema"][0]
    record["meta"]["id"] = "6f1c0000-0000-4000-8000-000000000001"
    assert record == example("lm-minimal.estrec.json")


@pytest.mark.parametrize("name", ["lm-minimal", "dfeols-linear-fe", "iv"])
def test_example_records_validate(name):
    assert profile_errors(example(f"{name}.estrec.json")) == []


# ---------------------------------------------------------------- core rules


def test_core_required_and_encodings():
    rec = example("lm-minimal.estrec.json")
    assert errors(CORE, {k: v for k, v in rec.items() if k != "parameters"})
    bad = copy.deepcopy(rec)
    bad["meta"]["status"] = "fine"
    assert errors(CORE, bad)
    ok = copy.deepcopy(rec)
    ok["parameters"][0]["estimate"] = "NaN"
    ok["parameters"][1]["p_value"] = None
    ok["metrics"]["custom_metric"] = {"value": "Inf", "definition": "unregistered names are allowed"}
    assert errors(CORE, ok) == []
    ok["parameters"][0]["estimate"] = "nan"
    assert errors(CORE, ok)


def test_core_canonical_constant():
    """The constant's canonical form has no factors; every other term needs one (Ted, 2026-10-24)."""
    assert not errors(CORE, {"name": "(Intercept)", "factors": []}, "canonical_term")
    assert errors(CORE, {"name": "x", "factors": []}, "canonical_term")
    assert errors(CORE, {"name": "(Intercept)", "factors": [{"variable": "x"}]}, "canonical_term")
    assert not errors(CORE, {"name": "x", "factors": [{"variable": "x"}]}, "canonical_term")


def test_core_checksum_in_memory_needs_method():
    c = {"algorithm": "xxhash64", "value": "ab12", "of": "in-memory"}
    assert errors(CORE, c, "checksum")
    assert errors(CORE, {**c, "method": 'R digest::digest(df, "xxhash64")'}, "checksum") == []
    assert errors(CORE, {"algorithm": "sha256", "value": "ab12", "of": "file"}, "checksum") == []


def test_core_structures():
    link = {
        "kind": "link",
        "attachment": "vcov_full",
        "spilled_kind": "matrix",
        "type": "CRV1",
        "ssc": {"convention": "fixest"},
        "default": True,
    }
    assert errors(CORE, {"vcov": [link]}, "structures") == []
    assert errors(CORE, {"vcov": [{"kind": "link"}]}, "structures")  # no attachment
    assert errors(CORE, {"vcov": [{"kind": "matrix", "type": "iid"}]}, "structures")  # no data
    assert errors(CORE, {"other": {"kind": "table", "columns": ["a"], "rows": [[1]]}}, "structures") == []
    assert errors(CORE, {"other": {"kind": "blob"}}, "structures")


def test_core_publication():
    pub = doc_examples()["publication"][0]["publication"]
    assert errors(CORE, {**pub, "locators": [pub["locator"], pub["locator"]]}, "publication")  # not both
    bad = copy.deepcopy(pub)
    bad["citation"]["author"].append("...")
    assert errors(CORE, bad, "publication")
    no_id = copy.deepcopy(pub)
    del no_id["citation"]["id"]
    assert errors(CORE, no_id, "publication") == []  # CSL requires id; this schema doesn't


def test_core_redacted_values_validate():
    rec = example("dfeols-linear-fe.estrec.json")
    h = "hmac-sha256:" + "0" * 64
    rec["provenance"]["agent"] = h
    rec["provenance"]["execution"]["invocation"]["argv"] = h
    rec["provenance"]["execution"]["workers"][0]["host"] = h
    assert errors(CORE, rec) == []


# ---------------------------------------------------------------- profiles


def test_inference_requires():
    rec = example("lm-minimal.estrec.json")
    p = PROFILES["inference/0.1"]
    for path in (
        ("metrics", "nobs"),
        ("metrics", "df_residual"),
        ("parameters", 0, "std_error"),
        ("structures", "vcov", 0, "ssc"),
        ("structures", "vcov", 0, "type"),
    ):
        bad = copy.deepcopy(rec)
        node = bad
        for k in path[:-1]:
            node = node[k]
        del node[path[-1]]
        assert errors(p, bad), path
    dropped = copy.deepcopy(rec)
    dropped["parameters"].append({"term": "o.x", "dropped": "collinear"})
    assert errors(p, dropped) == []


def test_inference_df_residual_optional_for_z_tests():
    rec = example("lm-minimal.estrec.json")
    p = PROFILES["inference/0.1"]
    z = copy.deepcopy(rec)
    del z["metrics"]["df_residual"]
    assert errors(p, z)  # df_t 30: t tests need df_residual
    z["structures"]["vcov"][0]["df_t"] = None
    assert errors(p, z) == []
    del z["structures"]["vcov"][0]["df_t"]
    assert errors(p, z) == []
    two = example("dfeols-linear-fe.estrec.json")
    del two["metrics"]["df_residual"]
    two["structures"]["vcov"][1]["df_t"] = None  # not the default
    assert errors(p, two)
    two["structures"]["vcov"][0]["df_t"] = None
    assert errors(p, two) == []


def test_inference_default_vcov():
    rec = example("dfeols-linear-fe.estrec.json")
    p = PROFILES["inference/0.1"]
    two_defaults = copy.deepcopy(rec)
    two_defaults["structures"]["vcov"][1]["default"] = True
    assert errors(p, two_defaults)
    no_default = copy.deepcopy(rec)
    no_default["structures"]["vcov"][0]["default"] = False
    assert errors(p, no_default)  # two vcovs, none marked
    default_without_ssc = copy.deepcopy(rec)
    del default_without_ssc["structures"]["vcov"][0]["ssc"]["convention"]
    assert errors(p, default_without_ssc)


def test_linear_fe_requires():
    rec = example("dfeols-linear-fe.estrec.json")
    p = PROFILES["linear-fe/0.1"]
    assert errors(p, rec) == []
    for path in (
        ("specification", "options", "drop_singletons"),
        ("structures", "fixed_effects", 0, "levels"),
    ):
        bad = copy.deepcopy(rec)
        node = bad
        for k in path[:-1]:
            node = node[k]
        del node[path[-1]]
        assert errors(p, bad), path
    # n_singletons is expected, not required (pyfixest and fixest don't store it)
    no_singletons = copy.deepcopy(rec)
    del no_singletons["metrics"]["n_singletons"]
    assert errors(p, no_singletons) == []
    # Convergence is vocabulary, not required (pyfixest, Stata areg/xtreg don't report it)
    no_count = copy.deepcopy(rec)
    del no_count["structures"]["numerics"]["iterations"]
    del no_count["structures"]["numerics"]["converged"]
    assert errors(p, no_count) == []
    no_numerics = copy.deepcopy(rec)
    del no_numerics["structures"]["numerics"]
    assert errors(p, no_numerics) == []


def test_iv_and_dfeols_require():
    iv = example("iv.estrec.json")
    p = PROFILES["iv/0.1"]
    for key in ("endogenous", "instruments"):
        bad = copy.deepcopy(iv)
        del bad["specification"][key]
        assert errors(p, bad), key
    # first-stage tests and structures.first_stage are expected, not required: most tools
    # compute them only on request
    no_first = copy.deepcopy(iv)
    del no_first["structures"]["first_stage"]
    del no_first["tests"]
    assert errors(p, no_first) == []
    bad = copy.deepcopy(iv)
    del bad["structures"]["first_stage"]["per_endogenous"][0]["endogenous"]
    assert errors(p, bad)
    bad = copy.deepcopy(iv)
    bad["tests"][2] = {"category": "endogeneity", "name": "wu_hausman"}  # no statistic or p_value
    assert errors(p, bad)

    rec = example("dfeols-linear-fe.estrec.json")
    p = PROFILES["dfeols/0.1"]
    bad = copy.deepcopy(rec)
    del bad["extensions"]["dfeols"]
    assert errors(p, bad)
    bad = copy.deepcopy(rec)
    bad["extensions"]["dfeols"]["absorption"]["firm"]["method"] = "global"
    assert errors(p, bad)
    bad = copy.deepcopy(rec)
    del bad["specification"]["options"]["drop_singletons"]  # linear-fe rules apply through dfeols
    assert errors(p, bad)


# ---------------------------------------------------------------- x-identifying (no jsonschema needed)


def test_identifying_marks_match_library():
    """The core's marks are the library's stand-in list."""
    from estrec import records as est

    marked = set(est.identifying_paths(load(CORE)))
    assert marked == set(est.DEFAULT_IDENTIFYING)
    assert not any(p.split(".")[0] in est.CORE for p in marked)  # redaction can't touch digest sections


def test_tests_section():
    """Core tests: a name and a statistic or p-value; profile rules on tests by category."""
    rec = example("survival-cox-efron.estrec.json")
    p = "profiles/survival-0.1.json"
    assert errors(p, rec) == []
    bad = copy.deepcopy(rec)
    del bad["tests"][1]["name"]
    assert errors(p, bad)
    bad = copy.deepcopy(rec)
    del bad["tests"][1]["options"]  # a proportional-hazards test needs its time transform
    assert errors(p, bad)
    rec = example("sem.estrec.json")
    p = "profiles/sem-0.1.json"
    bad = copy.deepcopy(rec)
    bad["tests"] = [t for t in bad["tests"] if t["category"] != "model_fit"]
    assert errors(p, bad)  # sem/0.1 requires the model chi-square

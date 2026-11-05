"""The worked converters in converters/: each tool's records validate, and the tools agree.

The same four specifications are fitted on one synthetic panel (two fixed effects, three
singletons, two rows with a missing value, a factor, an interaction, weights) in pyfixest,
fixest (R) and reghdfe (Stata). A tool that isn't installed is skipped: pyfixest needs the
package, fixest needs Rscript with fixest and jsonlite, reghdfe needs Stata (on PATH, or
$ESTIMATION_STATA) with reghdfe installed.

Across tools the records must agree on N, the singleton count, the coefficients and the
standard errors. Fields the tools define differently are recorded as {value, definition}
and not compared (pyfixest sigma; df_residual, which is min(G) - 1 under clustering in
pyfixest and reghdfe but N - K in fixest).
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import estimation_format as ef

ROOT = Path(__file__).resolve().parents[1]
CONVERTERS = ROOT / "converters"

# name: (pyfixest formula, vcov, weights; fixest call; reghdfe command)
SPECS = {
    "twofe_crv": (
        ("y ~ x1 + x2 | f1 + f2", {"CRV1": "g"}, None),
        "feols(y ~ x1 + x2 | f1 + f2, d, cluster = ~g)",
        "reghdfe y x1 x2, absorb(f1 f2) vce(cluster g)",
    ),
    "factor_weights": (
        ("y ~ x1 + i(k) + x1:x2 | f1", {"CRV1": "g"}, "w"),
        "feols(y ~ x1 + i(k) + x1:x2 | f1, d, cluster = ~g, weights = ~w)",
        "reghdfe y x1 i.k c.x1#c.x2 [aw=w], absorb(f1) vce(cluster g)",
    ),
    "twofe_iid": (
        ("y ~ x1 | f1 + f2", "iid", None),
        'feols(y ~ x1 | f1 + f2, d, vcov = "iid")',
        "reghdfe y x1, absorb(f1 f2)",
    ),
    "twofe_hc1": (
        ("y ~ x1 + x2 | f1 + f2", "hetero", None),
        'feols(y ~ x1 + x2 | f1 + f2, d, vcov = "hetero")',
        "reghdfe y x1 x2, absorb(f1 f2) vce(robust)",
    ),
}


def _stata() -> str | None:
    env = os.environ.get("ESTIMATION_STATA")
    if env:
        return env
    for name in ("stata-mp", "stata-se", "stata"):
        if shutil.which(name):
            return shutil.which(name)
    for path in sorted(Path("/usr/local").glob("stata*/stata-mp"), reverse=True):
        return str(path)
    return None


@pytest.fixture(scope="module")
def panel(tmp_path_factory) -> Path:
    np = pytest.importorskip("numpy")
    rng = np.random.default_rng(7)
    n = 3000
    cols = {
        "f1": rng.integers(1, 80, n),
        "f2": rng.integers(1, 15, n),
        "g": rng.integers(1, 40, n),
        "k": rng.integers(0, 4, n),
        "x1": rng.normal(size=n),
        "x2": rng.normal(size=n),
        "w": rng.uniform(0.5, 2, n),
    }
    cols["f1"][:3] = [901, 902, 903]  # three singletons
    y = (
        cols["x1"]
        - 0.5 * cols["x2"]
        + 0.3 * cols["k"]
        + 0.2 * cols["x1"] * cols["x2"]
        + 0.02 * cols["f1"]
        + 0.1 * cols["f2"]
        + rng.normal(size=n)
    )
    cols["y"] = y
    x2 = cols["x2"].astype(object)
    x2[[10, 11]] = ""  # missing
    cols["x2"] = x2
    path = tmp_path_factory.mktemp("panel") / "panel.csv"
    names = list(cols)
    with path.open("w") as f:
        f.write(",".join(names) + "\n")
        for i in range(n):
            f.write(",".join(_cell(cols[c][i]) for c in names) + "\n")
    return path


def _cell(v) -> str:
    if isinstance(v, str):
        return v
    return str(int(v)) if float(v).is_integer() and abs(v) < 1e6 else repr(float(v))


def _check(path: Path) -> dict:
    rec = ef.read(path)
    errors = [i for i in ef.validate(rec, base_dir=path.parent) if i.level != "info"]
    assert not errors, f"{path.name}: {errors}"
    assert "linear-fe/0.1" in rec["meta"]["profiles"]
    return rec


@pytest.fixture(scope="module")
def pyfixest_records(panel, tmp_path_factory) -> dict:
    if importlib.util.find_spec("pyfixest") is None:
        pytest.skip("pyfixest not installed")
    import warnings

    import pandas as pd
    import pyfixest as pf

    sys.path.insert(0, str(CONVERTERS / "pyfixest"))
    try:
        from estimation_pyfixest import to_record
    finally:
        sys.path.pop(0)
    out = tmp_path_factory.mktemp("pyfixest")
    d = pd.read_csv(panel)
    recs = {}
    for name, ((fml, vcov, weights), _, _) in SPECS.items():
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            fit = pf.feols(fml, d, vcov=vcov, weights=weights)
        ef.write(to_record(fit, d), out / f"{name}.estimation.json")
        recs[name] = _check(out / f"{name}.estimation.json")
    return recs


@pytest.fixture(scope="module")
def fixest_records(panel, tmp_path_factory) -> dict:
    rscript = shutil.which("Rscript")
    if rscript is None:
        pytest.skip("Rscript not found")
    probe = subprocess.run(
        [rscript, "-e", "library(fixest); library(jsonlite)"], check=False, capture_output=True
    )
    if probe.returncode:
        pytest.skip("R packages fixest and jsonlite not installed")
    out = tmp_path_factory.mktemp("fixest")
    lines = [
        "suppressMessages(library(fixest))",
        f'source("{CONVERTERS / "fixest" / "estimation_fixest.R"}")',
        f'd <- read.csv("{panel}")',
    ]
    for name, (_, call, _) in SPECS.items():
        lines.append(f'estimation_write(estimation_record({call}), "{out / name}.estimation.json")')
    script = out / "run.R"
    script.write_text("\n".join(lines) + "\n")
    run = subprocess.run([rscript, str(script)], check=False, capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    return {name: _check(out / f"{name}.estimation.json") for name in SPECS}


@pytest.fixture(scope="module")
def reghdfe_records(panel, tmp_path_factory) -> dict:
    stata = _stata()
    if stata is None:
        pytest.skip("Stata not found (set ESTIMATION_STATA)")
    out = tmp_path_factory.mktemp("reghdfe")
    probe = out / "probe.do"
    probe.write_text("sysuse auto, clear\nreghdfe price weight, absorb(turn)\n")
    run = subprocess.run(
        [stata, "-b", "do", probe.name], cwd=out, check=False, capture_output=True, text=True
    )
    if "r(" in (out / "probe.log").read_text().split("end of do-file")[-1] or run.returncode:
        pytest.skip("reghdfe doesn't run in this Stata (install reghdfe, ftools and require)")
    lines = [
        f'adopath ++ "{CONVERTERS / "reghdfe"}"',
        f'import delimited using "{panel}", clear',
    ]
    for name, (_, _, cmd) in SPECS.items():
        lines += [cmd, f'estimation_write using "{out / name}.estimation.json", replace']
    (out / "run.do").write_text("\n".join(lines) + "\n")
    subprocess.run([stata, "-b", "do", "run.do"], cwd=out, check=False, capture_output=True, text=True)
    log = (out / "run.log").read_text()
    assert "\nr(" not in log, log[-3000:]
    return {name: _check(out / f"{name}.estimation.json") for name in SPECS}


def _value(x):
    return x["value"] if isinstance(x, dict) else x


def _compare(a: dict, b: dict, se_rtol: float) -> None:
    for key in ("nobs", "n_singletons"):
        assert a["metrics"][key] == b["metrics"][key], key
    assert _value(a["metrics"]["r2"]) == pytest.approx(_value(b["metrics"]["r2"]), rel=1e-7)
    assert a["structures"]["vcov"][0]["df_t"] == b["structures"]["vcov"][0]["df_t"]
    pa = {p["canonical"]["name"]: p for p in a["parameters"] if not p.get("dropped")}
    pb = {p["canonical"]["name"]: p for p in b["parameters"] if not p.get("dropped")}
    pa.pop("(Intercept)", None)  # reghdfe reports a constant with absorbed FEs; the others don't
    pb.pop("(Intercept)", None)
    assert set(pa) == set(pb)
    for term in pa:
        assert pa[term]["estimate"] == pytest.approx(pb[term]["estimate"], rel=1e-6), term
        assert pa[term]["std_error"] == pytest.approx(pb[term]["std_error"], rel=se_rtol), term


@pytest.mark.parametrize("spec", list(SPECS))
def test_pyfixest_matches_fixest(pyfixest_records, fixest_records, spec):
    _compare(pyfixest_records[spec], fixest_records[spec], se_rtol=1e-6)


@pytest.mark.parametrize("spec", list(SPECS))
def test_reghdfe_matches_fixest(reghdfe_records, fixest_records, spec):
    _compare(reghdfe_records[spec], fixest_records[spec], se_rtol=1e-6)


def test_singletons_and_missing(pyfixest_records):
    rec = pyfixest_records["twofe_crv"]
    assert rec["metrics"]["n_singletons"] == 3
    assert rec["specification"]["sample"]["dropped"] == {"missing": 2, "singletons": 3}


@pytest.mark.parametrize("spec", list(SPECS))
def test_model_f_in_tests(pyfixest_records, reghdfe_records, spec):
    """The model F is a test (category model). pyfixest and reghdfe agree on the statistic;
    each uses its own residual df as the denominator df. Without clustering those differ:
    pyfixest's _dfd is N - k - all FE levels, reghdfe's e(df_r) subtracts the redundant ones,
    so the p-values differ slightly."""
    from scipy.stats import f as f_dist

    ta, tb = (
        next(t for t in r[spec].get("tests", []) if t["category"] == "model")
        for r in (pyfixest_records, reghdfe_records)
    )
    assert ta["name"] == tb["name"] and ta["df1"] == tb["df1"]
    assert ta["statistic"] == pytest.approx(tb["statistic"], rel=1e-6)
    for t, r in ((ta, pyfixest_records[spec]), (tb, reghdfe_records[spec])):
        assert t["df2"] == _value(r["metrics"]["df_residual"])
        assert t["p_value"] == pytest.approx(
            f_dist.sf(t["statistic"], t["df1"], t["df2"]), rel=1e-6, abs=1e-300
        )


# ---------------------------------------------------------------- disclosure levels (spec 4.9)


def _clean(path: Path) -> dict:
    """Valid, with no warnings, and the level declared."""
    rec = ef.read(path)
    issues = [i for i in ef.validate(rec, base_dir=path.parent) if i.level != "info"]
    assert not issues, f"{path.name}: {issues}"
    return rec


@pytest.fixture(scope="module")
def fixest_levels(panel, tmp_path_factory) -> dict:
    rscript = shutil.which("Rscript")
    if rscript is None:
        pytest.skip("Rscript not found")
    if subprocess.run(
        [rscript, "-e", "library(fixest); library(jsonlite)"], check=False, capture_output=True
    ).returncode:
        pytest.skip("R packages fixest and jsonlite not installed")
    out = tmp_path_factory.mktemp("fixest-levels")
    call = SPECS["twofe_crv"][1]
    lines = [
        "suppressMessages(library(fixest))",
        f'source("{CONVERTERS / "fixest" / "estimation_fixest.R"}")',
        f'd <- read.csv("{panel}")',
        f"f <- {call}",
    ]
    lines += [
        f'estimation_write(estimation_record(f, level = {n}), "{out}/l{n}.estimation.json")'
        for n in range(1, 6)
    ]
    (out / "run.R").write_text("\n".join(lines) + "\n")
    run = subprocess.run([rscript, str(out / "run.R")], check=False, capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    return {n: _clean(out / f"l{n}.estimation.json") for n in range(1, 6)}


@pytest.mark.parametrize("level", [1, 2, 3, 4, 5])
def test_fixest_converter_levels(fixest_levels, level):
    rec = fixest_levels[level]
    assert rec["meta"]["disclosure"] == {"level": level}
    assert ef.record_level(rec) <= level
    names = [s["name"] for s in rec.get("provenance", {}).get("software", [])]
    if level == 4:
        assert names == ["fixest", "R", "estimation_fixest"] and "agent" not in rec["provenance"]
    if level >= 3:
        assert "linear-fe/0.1" in rec["meta"]["profiles"]


@pytest.mark.parametrize("level", [1, 2, 3, 4, 5])
def test_pyfixest_converter_levels(panel, tmp_path, level):
    if importlib.util.find_spec("pyfixest") is None:
        pytest.skip("pyfixest not installed")
    import warnings

    import pandas as pd
    import pyfixest as pf

    sys.path.insert(0, str(CONVERTERS / "pyfixest"))
    try:
        from estimation_pyfixest import to_record
    finally:
        sys.path.pop(0)
    d = pd.read_csv(panel)
    (fml, vcov, weights), _, _ = SPECS["twofe_crv"]
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        fit = pf.feols(fml, d, vcov=vcov, weights=weights)
        rec = to_record(fit, d, program="code/main.py", data_info={"name": "synthetic panel"})
        ef.write(rec, tmp_path / "r.estimation.json", level=level)
    out = _clean(tmp_path / "r.estimation.json")
    assert out["meta"]["disclosure"] == {"level": level}
    if level == 4:
        assert [s["name"] for s in out["provenance"]["software"]] == [
            "pyfixest",
            "python",
            "estimation_pyfixest",
        ]
        assert out["provenance"]["data"][0]["name"] == "synthetic panel"
        assert out["specification"]["program"] == {"path": "code/main.py"}


@pytest.fixture(scope="module")
def reghdfe_levels(panel, tmp_path_factory) -> dict:
    stata = _stata()
    if stata is None:
        pytest.skip("Stata not found (set ESTIMATION_STATA)")
    out = tmp_path_factory.mktemp("reghdfe-levels")
    lines = [
        f'adopath ++ "{CONVERTERS / "reghdfe"}"',
        f'import delimited using "{panel}", clear',
        SPECS["twofe_crv"][2],
    ]
    lines += [f'estimation_write using "{out}/l{n}.estimation.json", replace level({n})' for n in range(1, 6)]
    (out / "run.do").write_text("\n".join(lines) + "\n")
    subprocess.run([stata, "-b", "do", "run.do"], cwd=out, check=False, capture_output=True, text=True)
    log = (out / "run.log").read_text()
    if "reghdfe" in log and "unrecognized command" in log:
        pytest.skip("reghdfe isn't installed in this Stata")
    assert "\nr(" not in log, log[-3000:]
    return {n: _clean(out / f"l{n}.estimation.json") for n in range(1, 6)}


@pytest.mark.parametrize("level", [1, 2, 3, 4, 5])
def test_reghdfe_converter_levels(reghdfe_levels, level):
    rec = reghdfe_levels[level]
    assert rec["meta"]["disclosure"] == {"level": level}
    assert ef.record_level(rec) <= level
    if level == 4:
        names = [s["name"] for s in rec["provenance"]["software"]]
        assert names == ["reghdfe", "stata", "estimation_write"] and "agent" not in rec["provenance"]
    if level == 1:
        assert set(rec) == {"schema", "meta", "metrics", "parameters", "history"}


def test_reghdfe_rejects_a_bad_level(panel, tmp_path):
    stata = _stata()
    if stata is None:
        pytest.skip("Stata not found (set ESTIMATION_STATA)")
    lines = [
        f'adopath ++ "{CONVERTERS / "reghdfe"}"',
        f'import delimited using "{panel}", clear',
        SPECS["twofe_iid"][2],
        f'capture noisily estimation_write using "{tmp_path}/x.json", level(6)',
        'display "rc=" _rc',
    ]
    (tmp_path / "bad.do").write_text("\n".join(lines) + "\n")
    subprocess.run([stata, "-b", "do", "bad.do"], cwd=tmp_path, check=False, capture_output=True, text=True)
    assert "rc=198" in (tmp_path / "bad.log").read_text()

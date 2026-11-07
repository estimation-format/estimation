"""estrec for Stata (stata/estrec.ado): every supported command writes a valid record.

Each command runs on Stata's auto data (plus a count and a panel id). The records must
validate with no warnings at every disclosure level (but glm/0.1's missing deviance after
commands that post none), claim the profiles listed below, and
reproduce Stata's own results table (r(table)) to rounding. reghdfe records must equal the
worked converter's (converters/reghdfe) apart from the writer's name and the formula text.

Needs Stata (on PATH, or $ESTREC_STATA). Commands from SSC (reghdfe, ivreg2, ivreghdfe)
are skipped when they aren't installed.
"""

from __future__ import annotations

import csv
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

import pytest

import estrec as ef

ROOT = Path(__file__).resolve().parents[1]
STATA_DIR = ROOT / "stata"

INF = "inference/0.1"
FE = "linear-fe/0.1"
IV = "iv/0.1"
GLM = "glm/0.1"

# name: (command, profiles at level 4, needs)
CASES = {
    "regress_crv": ("regress price mpg weight i.rep78, vce(cluster id)", [INF], None),
    "regress_hc3_aw": ("regress price mpg weight [aw=turn], vce(hc3)", [INF], None),
    "regress_fw": ("regress price mpg [fw=rep78]", [INF], None),
    "areg_crv": ("areg price mpg weight, absorb(rep78) vce(cluster id)", [INF, FE], None),
    "xtreg_fe": ("xtreg price mpg weight, fe", [INF, FE], None),
    "xtreg_fe_robust": ("xtreg price mpg weight, fe vce(robust)", [INF, FE], None),
    "xtreg_re": ("xtreg price mpg weight, re vce(robust)", [INF], None),
    "reghdfe": ("reghdfe price mpg weight, absorb(rep78 id) vce(cluster id)", [INF, FE], "reghdfe"),
    "ivregress_2sls": ("ivregress 2sls price weight (mpg = length turn)", [INF, IV], None),
    "ivregress_liml": ("ivregress liml price weight (mpg = length turn), small vce(robust)", [INF, IV], None),
    "ivregress_gmm": ("ivregress gmm price weight (mpg = length turn)", [INF, IV], None),
    "ivreg2_robust": ("ivreg2 price weight (mpg = length turn), robust first", [INF, IV], "ivreg2"),
    "ivreg2_endog": ("ivreg2 price weight (mpg = length turn), endog(mpg) ffirst", [INF, IV], "ivreg2"),
    "ivreghdfe": (
        "ivreghdfe price weight (mpg = length turn), absorb(rep78) cluster(id) first",
        [INF, IV, FE],
        "ivreghdfe",
    ),
    "logit": ("logit foreign mpg weight", [INF, GLM], None),
    "logistic": ("logistic foreign mpg i.rep78", [INF, GLM], None),
    "probit": ("probit foreign mpg weight, vce(robust)", [INF, GLM], None),
    "poisson": ("poisson cnt mpg weight, exposure(length)", [INF, GLM], None),
    "nbreg": ("nbreg cnt mpg weight, vce(cluster id)", [INF, GLM], None),
    "glm": ("glm cnt mpg weight, family(poisson) link(log)", [INF, GLM], None),
    "glm_irls": ("glm foreign mpg weight, family(binomial) link(logit) irls", [INF], None),
    "tobit": ("tobit price mpg, ll(3500)", None, None),
}

# These post no deviance and estrec computes none, so glm/0.1 warns that it is missing
NO_DEVIANCE = {"logit", "logistic", "probit", "poisson", "nbreg"}
# z tests: no e(df_r), so no df_residual and a null df_t (inference/0.1)
Z_TESTS = NO_DEVIANCE | {"xtreg_re", "ivregress_2sls", "ivregress_gmm", "ivreg2_robust", "ivreg2_endog"}

SETUP = """
set linesize 200
sysuse auto, clear
generate cnt = round(price/1000)
generate id = mod(_n, 15) + 1
generate t = ceil(_n/15)
xtset id t
"""


def _stata() -> str | None:
    env = os.environ.get("ESTREC_STATA")
    if env:
        return env
    for name in ("stata-mp", "stata-se", "stata"):
        if shutil.which(name):
            return shutil.which(name)
    for path in sorted(Path("/usr/local").glob("stata*/stata-mp"), reverse=True):
        return str(path)
    return None


def _run(stata: str, out: Path, body: str, name: str = "run") -> str:
    (out / f"{name}.do").write_text(f'adopath ++ "{STATA_DIR}"\n' + body + "\n")
    subprocess.run([stata, "-b", "do", f"{name}.do"], cwd=out, check=False, capture_output=True, text=True)
    return (out / f"{name}.log").read_text()


@pytest.fixture(scope="module")
def stata() -> str:
    path = _stata()
    if path is None:
        pytest.skip("Stata not found (set ESTREC_STATA)")
    return path


@pytest.fixture(scope="module")
def installed(stata, tmp_path_factory) -> set:
    out = tmp_path_factory.mktemp("probe")
    log = _run(
        stata, out, "foreach p in reghdfe ivreg2 ivreghdfe {\ncapture which `p'\nif !_rc di \"HAVE `p'\"\n}"
    )
    return {line.split()[1] for line in log.splitlines() if line.startswith("HAVE ")}


@pytest.fixture(scope="module")
def written(stata, installed, tmp_path_factory) -> Path:
    """Every case at levels 1-5, plus r(table) as CSV."""
    out = tmp_path_factory.mktemp("estrec")
    lines = [SETUP]
    for name, (cmd, _, needs) in CASES.items():
        if needs and needs not in installed:
            continue
        lines += [
            f"quietly {cmd}",
            "capture matrix T = r(table)",
            "if _rc matrix T = J(6, 0, .)",
            (
                f'mata: _T = st_matrix("T"); _f = fopen("{name}.csv", "w"); '
                "for (_j = 1; _j <= cols(_T) & rows(_T) >= 6; _j++) "
                'fput(_f, invtokens(strofreal(_T[(1, 2, 3, 4, 5, 6), _j]\', "%24.17g"), ",")); fclose(_f)'
            ),
        ]
        lines += [f'estrec write using "{name}_l{n}.estrec.json", replace level({n})' for n in range(1, 6)]
    log = _run(stata, out, "\n".join(lines))
    assert "\nr(" not in log, log[-3000:]
    return out


def _case(written: Path, installed: set, name: str, level: int = 4) -> dict:
    needs = CASES[name][2]
    if needs and needs not in installed:
        pytest.skip(f"{needs} isn't installed in this Stata")
    path = written / f"{name}_l{level}.estrec.json"
    rec = ef.read(path)
    issues = [i for i in ef.validate(rec, base_dir=path.parent) if i.level != "info"]
    if name in NO_DEVIANCE:
        issues = [i for i in issues if not (i.level == "warning" and i.path == "metrics.deviance")]
    assert not issues, f"{path.name}: {issues}"
    assert rec["meta"]["disclosure"] == {"level": level}
    assert ef.record_level(rec) <= level
    return rec


@pytest.mark.parametrize("level", [1, 2, 3, 4, 5])
@pytest.mark.parametrize("name", list(CASES))
def test_valid_at_every_level(written, installed, name, level):
    rec = _case(written, installed, name, level)
    if level == 4:
        assert rec["meta"].get("profiles") == CASES[name][1]
        assert [s["name"] for s in rec["provenance"]["software"]][1:] == ["stata", "estrec"]
    if level == 1:
        assert set(rec) == {"schema", "meta", "metrics", "parameters", "history"}


@pytest.mark.parametrize("name", list(CASES))
def test_matches_stata_results_table(written, installed, name):
    rec = _case(written, installed, name)
    with open(written / f"{name}.csv") as f:
        rows = [[None if x.startswith(".") else float(x) for x in r] for r in csv.reader(f)]
    if not rows:
        pytest.skip(f"{name} leaves no r(table)")
    keys = ("estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high")
    for p, row in zip(rec["parameters"], rows):
        if "estimate" not in p or "p_value" not in p:
            continue
        got = [p[k] for k in keys]
        if name == "logistic":  # Stata shows odds ratios; the record keeps log-odds (spec 4.4)
            b = math.exp(p["estimate"])
            got = [
                b,
                b * p["std_error"],
                p["statistic"],
                p["p_value"],
                math.exp(p["conf_low"]),
                math.exp(p["conf_high"]),
            ]
        for g, want in zip(got, row):
            if want is not None:
                assert g == pytest.approx(want, rel=1e-10, abs=1e-12), (p["term"], g, want)


def _tests(rec: dict) -> dict:
    return {(t["category"], t["name"], t.get("distribution")): t for t in rec.get("tests", [])}


def test_xtreg_fe_tests_use_regressor_df(written, installed):
    rec = _case(written, installed, "xtreg_fe")
    tests = _tests(rec)
    assert tests[("model", "f", "F")]["df1"] == 2  # Stata shows F(2,57); e(df_m) is 16
    assert tests[("fixed_effects", "f", "F")]["df1"] == 14
    fe = rec["structures"]["fixed_effects"][0]
    assert fe["name"] == "id" and fe["levels"] == 15
    assert rec["specification"]["state"]["xtset"] == {"panelvar": "id", "timevar": "t"}


def test_areg_counts_absorbed_levels(written, installed):
    rec = _case(written, installed, "areg_crv")
    vc = rec["structures"]["vcov"][0]
    assert vc["type"] == "CRV1" and "nested" in vc["ssc"]["K_counts"]
    assert rec["specification"]["options"]["drop_singletons"] is False


def test_regress_keeps_the_model_based_vcov(written, installed):
    rec = _case(written, installed, "regress_crv")
    default, model = rec["structures"]["vcov"]
    assert default["type"] == "CRV1" and default["default"] and default["df_t"] == 14
    assert model["type"] == "iid" and not model["default"] and model["df_t"] == 69 - 7


def test_frequency_weights_count_rows(written, installed):
    rec = _case(written, installed, "regress_fw")
    assert rec["metrics"]["nobs"]["value"] == 69 and rec["metrics"]["sum_weights"] == 235


def test_ivregress_records_estat(written, installed):
    rec = _case(written, installed, "ivregress_2sls")
    tests = _tests(rec)
    assert {
        ("first_stage", "f", "F"),
        ("overidentification", "sargan", "chi2"),
        ("endogeneity", "wu_hausman", "F"),
        ("weak_identification", "cragg_donald_f", None),
    } <= set(tests)
    assert rec["structures"]["vcov"][0]["df_t"] is None  # z tests without small
    assert "df_residual" not in rec["metrics"]
    assert rec["specification"]["instruments"] == ["length", "turn"]
    assert rec["specification"]["endogenous"] == ["mpg"]


def test_ivreg2_tests(written, installed):
    rec = _case(written, installed, "ivreg2_robust")
    tests = _tests(rec)
    assert ("overidentification", "hansen_j", "chi2") in tests
    assert ("weak_identification", "kleibergen_paap_rk_wald_f", None) in tests
    assert ("first_stage", "sanderson_windmeijer_f", "F") in tests
    assert rec["structures"]["vcov"][0]["type"] == "HC0"
    iid = _tests(_case(written, installed, "ivreg2_endog"))
    assert ("overidentification", "sargan", "chi2") in iid and ("endogeneity", "c", "chi2") in iid


def test_glm_family(written, installed):
    nb = _case(written, installed, "nbreg")
    assert nb["meta"]["estimator"]["distribution"] == "negative_binomial"
    aux = [p for p in nb["parameters"] if p["term"] == "/lnalpha"]
    assert aux and aux[0]["component"] == "auxiliary"
    po = _case(written, installed, "poisson")
    assert po["specification"]["offset"] == {"variable": "length", "exposure": True}
    assert po["structures"]["numerics"]["converged"] is True
    irls = _case(written, installed, "glm_irls")
    assert irls["meta"]["messages"][0]["code"] == "convergence_unknown"


@pytest.mark.parametrize("name", sorted(Z_TESTS))
def test_z_tests_record_no_residual_df(written, installed, name):
    rec = _case(written, installed, name)
    assert "df_residual" not in rec["metrics"]
    assert rec["structures"]["vcov"][0]["df_t"] is None


def test_deviance_only_when_posted(written, installed):
    for name in sorted(NO_DEVIANCE):
        assert "deviance" not in _case(written, installed, name)["metrics"], name
    glm = _case(written, installed, "glm")
    assert isinstance(glm["metrics"]["deviance"], float)


def test_unmapped_command_is_core_only(written, installed):
    rec = _case(written, installed, "tobit")
    assert "profiles" not in rec["meta"]
    aux = [p for p in rec["parameters"] if p["term"].startswith("/")]
    assert aux and "p_value" not in aux[0]


def _flat(d, p=""):
    if isinstance(d, dict):
        return {k2: v2 for k, v in d.items() for k2, v2 in _flat(v, f"{p}.{k}").items()}
    if isinstance(d, list):
        return {k2: v2 for i, v in enumerate(d) for k2, v2 in _flat(v, f"{p}[{i}]").items()}
    return {p: d}


def test_reghdfe_matches_the_worked_converter(stata, installed, tmp_path):
    if "reghdfe" not in installed:
        pytest.skip("reghdfe isn't installed in this Stata")
    cmds = [
        "reghdfe price mpg weight, absorb(rep78 id) vce(cluster id)",
        "reghdfe price mpg i.foreign c.mpg#c.weight [aw=turn], absorb(rep78) vce(robust)",
    ]
    lines = [f'adopath ++ "{ROOT / "converters" / "reghdfe"}"', SETUP]
    for i, cmd in enumerate(cmds):
        lines.append(f"quietly {cmd}")
        for n in (1, 3, 5):
            lines += [
                f'estimation_write using "old{i}_{n}.json", replace level({n})',
                f'estrec write using "new{i}_{n}.json", replace level({n})',
            ]
    log = _run(stata, tmp_path, "\n".join(lines))
    assert "\nr(" not in log, log[-3000:]
    allowed = {
        ".meta.id",
        ".meta.created",
        ".history[0].when",
        ".history[0].by.name",
        ".history[0].by.version",
        ".meta.producer.name",
        ".meta.producer.version",
        ".provenance.software[2].name",
        ".provenance.software[2].version",
        ".specification.formula.text",
    }
    for i in range(len(cmds)):
        for n in (1, 3, 5):
            old = _flat(json.loads((tmp_path / f"old{i}_{n}.json").read_text()))
            new = _flat(json.loads((tmp_path / f"new{i}_{n}.json").read_text()))
            diff = [k for k in sorted(set(old) | set(new)) if old.get(k) != new.get(k) and k not in allowed]
            assert not diff, (cmds[i], n, diff)


@pytest.mark.parametrize(
    "setup, call, rc",
    [
        ("regress price mpg", 'estrec write using "x.json", level(6)', 198),
        ("ereturn clear", 'estrec write using "x.json"', 301),
        ("svyset _n\nsvy: regress price mpg", 'estrec write using "x.json"', 198),
        ('regress price mpg\nestrec write using "x.json"', 'estrec write using "x.json"', 602),
        ("", "estrec frobnicate", 199),
    ],
)
def test_errors(stata, tmp_path, setup, call, rc):
    log = _run(stata, tmp_path, f'sysuse auto, clear\n{setup}\ncapture noisily {call}\ndisplay "rc=" _rc')
    assert f"rc={rc}" in log, log[-1500:]

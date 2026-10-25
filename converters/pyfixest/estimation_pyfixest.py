"""pyfixest `Feols` fit -> `estimation` record (linear-fe/0.1).

A worked converter: it reads a fitted pyfixest model and returns the record as a dict,
using only what pyfixest stores (plus the input data, for the sample counts). Written
against pyfixest 0.60.0; private attributes (`_N`, `_vcov`, ...) are pyfixest's own and may
change between versions.

    import pyfixest as pf
    from estimation_pyfixest import to_record

    fit = pf.feols("y ~ x1 + x2 | firm + year", data, vcov={"CRV1": "firm"})
    rec = to_record(fit, data)

    import estimation_format as ef        # optional: adds the core digest, spills, checks
    ef.write(rec, "fit.estimation.json")

`data` is needed because pyfixest keeps only the rows it used: the rows dropped for missing
values and the singleton rows are one combined set (`_na_index`), and the only place the
singleton count appears is a warning. With the input data the converter tells them apart.
"""

from __future__ import annotations

import getpass
import platform
import re
import socket
import sys
import uuid
from datetime import datetime, timezone
from importlib import metadata
from typing import Any

import numpy as np

__version__ = "0.1.0"
CONVERTER = {"name": "estimation_pyfixest", "version": __version__}

# pyfixest vcov names -> the format's vocabulary (pyfixest "hetero" is HC1)
VCOV_TYPES = {"iid": "iid", "hetero": "HC1", "HC1": "HC1", "HC2": "HC2", "HC3": "HC3"}
WEIGHT_TYPES = {"aweights": "analytic", "fweights": "frequency"}
_FACTOR = (
    re.compile(r"^(?P<var>[^:\[\]]+)::(?P<level>.+)$"),  # i(k) -> k::1
    re.compile(r"^C\((?P<var>[^)]+)\)\[(?:T\.)?(?P<level>[^\]]+)\]$"),  # C(k)[T.1], C(k)[1]
)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _num(x: Any) -> Any:
    """numpy scalar -> Python; non-finite floats as the format's strings."""
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating, float)):
        x = float(x)
        if np.isnan(x):
            return "NaN"
        if np.isinf(x):
            return "Infinity" if x > 0 else "-Infinity"
        return x
    if isinstance(x, np.str_):
        return str(x)
    return x


def _split_term(term: str) -> list[str]:
    """Split an interaction on ':' but not on the '::' of i() levels."""
    return [p for p in re.split(r"(?<!:):(?!:)", term) if p]


def canonical(term: str) -> dict:
    """Canonical `{name, factors}` for a pyfixest term name (spec 4.4.1)."""
    if term == "Intercept":
        return {"name": "(Intercept)", "factors": []}
    factors = []
    for part in _split_term(term):
        for pat in _FACTOR:
            m = pat.match(part)
            if m:
                factors.append({"variable": m["var"], "level": m["level"]})
                break
        else:
            factors.append({"variable": part})
    levels = [f for f in factors if "level" in f]
    if levels and len(levels) < len(factors):
        # factor x continuous: Stata's form, in the order specified
        name = "#".join(
            f"{f['level']}.{f['variable']}" if "level" in f else f"c.{f['variable']}" for f in factors
        )
    else:
        name = ":".join(f["variable"] + f.get("level", "") for f in factors)
    return {"name": name, "factors": factors}


def _model_columns(fit, data) -> list[str]:
    """Data columns the model uses: identifiers in the formula, plus weights and clusters."""
    names = set(re.findall(r"[A-Za-z_.][A-Za-z0-9_.]*", fit._fml))
    if fit._weights_name:
        names.add(fit._weights_name)
    if fit._is_clustered:
        names.update(fit._clustervar)
    return [c for c in data.columns if c in names]


def _sample(fit, data) -> dict:
    rows_input = len(data)
    dropped = len(fit._na_index)
    n_missing = int(data[_model_columns(fit, data)].isna().any(axis=1).sum())
    n_singletons = dropped - n_missing if fit._drop_singletons else 0
    if fit._N + n_missing + n_singletons != rows_input:
        raise ValueError(
            f"sample counts don't add up: {rows_input} input rows, {fit._N} used, "
            f"{n_missing} with missing values, {n_singletons} singletons. Pass the data the "
            "model was fitted on, unchanged."
        )
    return {"rows_input": rows_input, "n_missing": n_missing, "n_singletons": n_singletons}


def _vcov(fit) -> dict:
    detail = fit._vcov_type_detail
    labels = [str(c) for c in fit._coefnames]
    v: dict[str, Any] = {
        "kind": "matrix",
        "labels": labels,
        "data": [[_num(x) for x in row] for row in np.asarray(fit._vcov)],
        "type": VCOV_TYPES.get(detail, detail),
    }
    if v["type"] != detail:
        v["tool_type"] = detail
    ssc = np.asarray(fit._ssc).ravel()
    factors: dict[str, Any] = {k: _num(x) for k, x in fit._ssc_dict.items()}
    if fit._is_clustered:
        G = [int(g) for g in fit._G[: len(fit._clustervar)]]
        v["cluster"] = list(fit._clustervar)
        v["n_clusters"] = dict(zip(fit._clustervar, G))
        v["n_clusters_min"] = min(G)
    if len(ssc) == 1:
        factors["adjustment"] = _num(ssc[0])
    else:  # multiway clustering: one signed factor per component (pyfixest _ssc)
        factors["adjustment_components"] = [_num(x) for x in ssc]
    v["ssc"] = {
        "convention": "pyfixest",
        "formula": "k_adj: (N-1)/(N-df_k) (N/(N-df_k) for hetero); G_adj: G/(G-1) for CRV",
        "factors": factors,
        "K_counts": {"df_k": _num(fit._df_k), "k_fixef": fit._ssc_dict.get("k_fixef")},
    }
    v["df_t"] = _num(fit._df_t)
    v["default"] = True
    return v


def _fixed_effects(fit) -> list[dict]:
    if not fit._has_fixef:
        return []
    return [
        {"kind": "object", "name": str(name), "levels": int(fit._fe[name].nunique())}
        for name in fit._fe.columns
    ]


def _software() -> list[dict]:
    out = []
    for name, role in [
        ("pyfixest", "estimator"),
        ("numpy", "dependency"),
        ("scipy", "dependency"),
        ("pandas", "dependency"),
        ("formulaic", "dependency"),
        ("narwhals", "dependency"),
    ]:
        try:
            ver = metadata.version(name)
        except metadata.PackageNotFoundError:
            continue
        out.append(
            {"name": name, "version": ver, "purl": f"pkg:pypi/{name}@{ver}", "role": role, "source": "PyPI"}
        )
    py = platform.python_version()
    out.insert(1, {"name": "python", "version": py, "purl": f"pkg:generic/python@{py}", "role": "language"})
    return out


def to_record(
    fit,
    data,
    *,
    call: str | None = None,
    identifying: bool = True,
    publication: dict | None = None,
) -> dict:
    """The `estimation` record for one pyfixest `Feols` fit.

    `data` is the frame the model was fitted on (for the missing/singleton counts). `call`
    is the command as written, if you have it. `identifying=False` leaves out the user and
    host (they can also be removed later with `estimation redact`).
    """
    if getattr(fit, "_is_iv", False) or fit._method != "feols":
        raise NotImplementedError("only OLS feols fits; IV and GLMs need the iv profile or others")
    if hasattr(fit, "all_fitted_models"):
        raise TypeError("a FixestMulti: convert each model in fit.all_fitted_models.values()")
    sample = _sample(fit, data)
    has_fe = fit._has_fixef
    profiles = ["inference/0.1", "linear-fe/0.1"] if has_fe else ["inference/0.1"]

    tidy = fit.tidy(alpha=0.05)
    collinear = [str(c) for c in fit._collin_vars]
    parameters = []
    for term, row in tidy.iterrows():
        term = str(term)
        parameters.append(
            {
                "term": term,
                "canonical": canonical(term),
                "estimate": _num(row["Estimate"]),
                "std_error": _num(row["Std. Error"]),
                "statistic": _num(row["t value"]),
                "p_value": _num(row["Pr(>|t|)"]),
                "conf_low": _num(row["2.5%"]),
                "conf_high": _num(row["97.5%"]),
            }
        )
    parameters += [{"term": t, "canonical": canonical(t), "dropped": "collinear"} for t in collinear]

    weights = None
    if fit._has_weights:
        weights = {
            "variable": fit._weights_name,
            "type": WEIGHT_TYPES.get(fit._weights_type, fit._weights_type),
        }
    fes = [f.strip() for f in fit._fixef.split("+")] if has_fe else []
    dfd_def = (
        "min(G) - 1 (pyfixest _dfd, clustered)"
        if fit._is_clustered
        else "N - k - sum of FE levels (pyfixest _dfd, the Wald test's denominator df)"
    )

    metrics: dict[str, Any] = {
        "nobs": int(fit._N),
        "n_singletons": sample["n_singletons"],
        "df_residual": {"value": _num(fit._dfd), "definition": dfd_def},
        "r2": _num(fit._r2),
        "adj_r2": _num(fit._adj_r2),
        # pyfixest _rmse is sqrt(RSS / N); fixest sigma() and reghdfe e(rmse) divide by the residual df
        "sigma": {"value": _num(fit._rmse), "definition": "sqrt(RSS / N) (pyfixest _rmse)"},
        "f_stat": {
            "value": _num(fit._f_statistic),
            "definition": f"Wald F of all coefficients with the default vcov, df ({fit._dfn}, {fit._dfd})",
        },
        "conf_level": 0.95,
    }
    if has_fe:
        metrics["r2_within"] = _num(fit._r2_within)
        metrics["adj_r2_within"] = _num(fit._adj_r2_within)

    options: dict[str, Any] = {
        "drop_singletons": bool(fit._drop_singletons),
        "fixef_rm": "singleton" if fit._drop_singletons else "none",
        "collinearity_tolerance": _num(fit._collin_tol),
    }
    if fit._has_weights:
        options["weights_type"] = fit._weights_type
    if has_fe:
        options["tolerance"] = _num(fit._fixef_tol)
        options["max_iterations"] = int(fit._fixef_maxiter)

    specification: dict[str, Any] = {
        "formula": {"text": fit._fml, "syntax": "fixest"},
        "terms": [str(c) for c in fit._coefnames],
        "weights": weights,
        "fixed_effects": fes,
        "clusters": list(fit._clustervar) if fit._is_clustered else [],
        "sample": {
            "restriction": None,
            "rows_input": sample["rows_input"],
            "dropped": {"missing": sample["n_missing"], "singletons": sample["n_singletons"]},
        },
        "options": options,
    }
    if call:
        specification["call"] = call

    structures: dict[str, Any] = {"vcov": [_vcov(fit)]}
    if has_fe:
        structures["fixed_effects"] = _fixed_effects(fit)
        demeaner = getattr(fit, "_demeaner", None)
        structures["numerics"] = {
            "kind": "object",
            "iterative": True,
            "algorithm": "map",
            "implementation": {
                "demeaner": type(demeaner).__name__,
                "backend": getattr(demeaner, "backend", None),
            },
            "tolerance": _num(fit._fixef_tol),
            "max_iterations": int(fit._fixef_maxiter),
            "collinearity_tolerance": _num(fit._collin_tol),
            "collinear_terms": collinear,
        }

    uname = platform.uname()
    provenance: dict[str, Any] = {
        "software": _software(),
        "environment": {"os": uname.system, "kernel": uname.release, "machine": uname.machine},
        "data": [
            {"role": "estimation", "rows": sample["rows_input"], "columns": [str(c) for c in data.columns]}
        ],
    }
    if identifying:
        provenance["agent"] = {"user": getpass.getuser(), "host": socket.gethostname()}
        provenance["execution"] = {"invocation": {"argv": list(sys.argv)}}

    messages = []
    if sample["n_singletons"]:
        messages.append(
            {
                "level": "info",
                "code": "singletons",
                "source": "pyfixest",
                "message": f"{sample['n_singletons']} singleton rows dropped",
            }
        )
    meta: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "created": _now(),
        "status": "ok",
        "estimator": {"family": "linear", "method": "ols"},
        "responses": [fit._depvar],
        "profiles": profiles,
    }
    if messages:
        meta["messages"] = messages

    record: dict[str, Any] = {
        "schema": "estimation/0.1",
        "meta": meta,
        "specification": specification,
        "metrics": metrics,
        "parameters": parameters,
        "structures": structures,
        "provenance": provenance,
    }
    if publication:
        record["publication"] = publication
    record["history"] = [
        {
            "when": meta["created"],
            "by": CONVERTER,
            "action": "created",
            "sections": [k for k in record if k not in ("schema", "history")],
        }
    ]
    return record

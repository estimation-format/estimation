// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ted Matherly and the estimation-format contributors
//
// Views of estimation records and table specs (spec/table.md) for the browser viewer and for
// node. The same rules as the Python reference (estimation_format.views and .table): tidy,
// glance, another vcov in the record, and building and rendering a table spec.
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.EstTable = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const TABLE_SCHEMA = "estimation-table/0.1";
  const DEFAULT_STARS = [0.1, 0.05, 0.01];
  const TABLE_METRICS = ["nobs", "r2", "adj_r2", "r2_within", "adj_r2_within", "pseudo_r2", "aic", "bic", "log_lik", "f_stat", "rmse"];
  const STAT_LABELS = {
    nobs: "N", r2: "R²", adj_r2: "Adj. R²", r2_within: "Within R²", adj_r2_within: "Adj. within R²",
    pseudo_r2: "Pseudo R²", aic: "AIC", bic: "BIC", log_lik: "Log lik.", rmse: "RMSE", f_stat: "F",
  };

  // lines under each estimate (spec/table.md section 5)
  const NAMED_LINES = { std_error: "({std_error})", statistic: "({statistic})", p_value: "[{p_value}]", conf_int: "[{conf_low}, {conf_high}]" };
  const PLACEHOLDERS = ["estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high"];
  const PLACEHOLDER = /\{([^{}]*)\}/g;
  const NAMED_NOTES = { std_error: "Standard errors in parentheses.", statistic: "Test statistics in parentheses.", p_value: "p-values in brackets.", conf_int: "Confidence intervals in brackets." };
  const WORDS = { estimate: "estimate", std_error: "standard error", statistic: "test statistic", p_value: "p-value", conf_low: "lower bound", conf_high: "upper bound" };

  function uncertaintyLines(spec) {
    const unc = spec.uncertainty === undefined ? "std_error" : spec.uncertainty;
    if (unc === null) return [];
    return (Array.isArray(unc) ? unc : [unc]).map((x) => NAMED_LINES[x] || x);
  }

  function lineIssues(spec) {
    const unc = spec.uncertainty === undefined ? "std_error" : spec.uncertainty;
    if (unc === null) return [];
    const items = Array.isArray(unc) ? unc : [unc];
    const out = [];
    items.forEach((x, j) => {
      const path = Array.isArray(unc) ? `uncertainty[${j}]` : "uncertainty";
      if (typeof x !== "string") out.push(issue("error", path, "a name or a template string"));
      else if (x in NAMED_LINES) return;
      else if (!x.includes("{")) out.push(issue("error", path, `'${x}' is neither a name (${Object.keys(NAMED_LINES).join(", ")}) nor a template`));
      else {
        const names = [...x.matchAll(PLACEHOLDER)].map((m) => m[1]);
        const bad = names.filter((n) => !PLACEHOLDERS.includes(n));
        if (bad.length) out.push(issue("error", path, `unknown placeholder {${bad[0]}}; use ${PLACEHOLDERS.join(", ")}`));
        else if (!names.length) out.push(issue("error", path, "a template needs at least one placeholder"));
      }
    });
    return out;
  }

  function uncertaintyNote(spec, lines) {
    const unc = spec.uncertainty === undefined ? "std_error" : spec.uncertainty;
    if (unc === null || !lines.length) return null;
    if (typeof unc === "string" && NAMED_NOTES[unc]) return NAMED_NOTES[unc];
    const parts = lines.map((t) => t.replace("{conf_low}, {conf_high}", "confidence interval").replace(PLACEHOLDER, (_, n) => WORDS[n] || n));
    return "Under each estimate: " + parts.join("; ") + ".";
  }

  // ------------------------------------------------------------ distributions

  const LANCZOS = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
    -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];

  function lgamma(x) {
    if (x < 0.5) return Math.log(Math.PI / Math.abs(Math.sin(Math.PI * x))) - lgamma(1 - x);
    x -= 1;
    let a = LANCZOS[0];
    const t = x + 7.5;
    for (let i = 1; i < 9; i++) a += LANCZOS[i] / (x + i);
    return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
  }

  // erfc to near double precision: a positive series for erf below 2.5, a continued fraction above
  function erfc(x) {
    if (x < 0) return 2 - erfc(-x);
    if (x < 2.5) {
      let term = x, sum = x;
      for (let n = 1; n < 200; n++) {
        term *= (2 * x * x) / (2 * n + 1);
        sum += term;
        if (term < sum * 1e-17) break;
      }
      return 1 - (2 / Math.sqrt(Math.PI)) * Math.exp(-x * x) * sum;
    }
    // Lentz: erfc(x) = exp(-x^2)/sqrt(pi) / (x + (1/2)/(x + 1/(x + (3/2)/(x + ...))))
    const tiny = 1e-300;
    let f = x, c = x, d = 0;
    for (let n = 1; n < 500; n++) {
      const a = n / 2;
      d = x + a * d; d = Math.abs(d) < tiny ? tiny : d; d = 1 / d;
      c = x + a / c; c = Math.abs(c) < tiny ? tiny : c;
      const delta = c * d;
      f *= delta;
      if (Math.abs(delta - 1) < 1e-16) break;
    }
    return Math.exp(-x * x) / Math.sqrt(Math.PI) / f;
  }

  function betacf(a, b, x) {
    const tiny = 1e-300;
    const qab = a + b, qap = a + 1, qam = a - 1;
    let c = 1, d = 1 - (qab * x) / qap;
    d = 1 / (Math.abs(d) > tiny ? d : tiny);
    let h = d;
    for (let m = 1; m < 10000; m++) {
      const m2 = 2 * m;
      let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
      d = 1 + aa * d; d = 1 / (Math.abs(d) > tiny ? d : tiny);
      c = 1 + aa / c; c = Math.abs(c) > tiny ? c : tiny;
      h *= d * c;
      aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
      d = 1 + aa * d; d = 1 / (Math.abs(d) > tiny ? d : tiny);
      c = 1 + aa / c; c = Math.abs(c) > tiny ? c : tiny;
      const delta = d * c;
      h *= delta;
      if (Math.abs(delta - 1) < 1e-15) break;
    }
    return h;
  }

  function lgammaRatioHalf(a) {
    if (a < 50) return lgamma(a + 0.5) - lgamma(a);
    return 0.5 * Math.log(a) - 1 / (8 * a) + 1 / (192 * a ** 3) - 1 / (640 * a ** 5);
  }

  function betaincHalf(a, x, logx, log1mx) {
    // I_x(a, 1/2)
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const lbt = lgammaRatioHalf(a) - lgamma(0.5) + a * logx + 0.5 * log1mx;
    if (x < (a + 1) / (a + 2.5)) return (Math.exp(lbt) * betacf(a, 0.5, x)) / a;
    return 1 - (Math.exp(lbt) * betacf(0.5, a, 1 - x)) / 0.5;
  }

  // P(|T| > |t|) for Student's t on df (normal when df is null or infinite)
  function twoSidedP(stat, df) {
    if (stat === null || stat === undefined || Number.isNaN(stat)) return NaN;
    const t = Math.abs(stat);
    if (!Number.isFinite(t)) return 0;
    if (df === null || df === undefined || !Number.isFinite(df)) return erfc(t / Math.SQRT2);
    if (t === 0) return 1;
    if (df >= 1e4) {
      // Hill (1970), ACM Algorithm 395
      const a = df - 0.5, b = 48 * a * a;
      let y = a * Math.log1p((t * t) / df);
      y = (((((-0.4 * y - 3.3) * y - 24) * y - 85.5) / (0.8 * y * y + 100 + b) + y + 3) / b + 1) * Math.sqrt(y);
      return erfc(y / Math.SQRT2);
    }
    const r = (t * t) / df;
    return betaincHalf(df / 2, 1 / (1 + r), -Math.log1p(r), Math.log(r) - Math.log1p(r));
  }

  // the normal quantile: Acklam's approximation with one Halley step on erfc
  function qnorm(p) {
    const a = [-3.969683028665376e1, 2.209460984245205e2, -2.759285104469687e2, 1.38357751867269e2, -3.066479806614716e1, 2.506628277459239];
    const b = [-5.447609879822406e1, 1.615858368580409e2, -1.556989798598866e2, 6.680131188771972e1, -1.328068155288572e1];
    const c = [-7.784894002430293e-3, -3.223964580411365e-1, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783];
    const d = [7.784695709041462e-3, 3.224671290700398e-1, 2.445134137142996, 3.754408661907416];
    const lo = 0.02425;
    let x;
    if (p < lo) {
      const q = Math.sqrt(-2 * Math.log(p));
      x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    } else if (p <= 1 - lo) {
      const q = p - 0.5, r = q * q;
      x = ((((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q) / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
    } else {
      const q = Math.sqrt(-2 * Math.log(1 - p));
      x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    }
    const e = 0.5 * erfc(-x / Math.SQRT2) - p;
    const u = e * Math.sqrt(2 * Math.PI) * Math.exp((x * x) / 2);
    return x - u / (1 + (x * u) / 2);
  }

  function criticalValue(level, df) {
    const alpha = 1 - level;
    const z = qnorm(1 - alpha / 2);
    if (df === null || df === undefined || !Number.isFinite(df)) return z;
    let lo = z, hi = Math.max(2 * z, 1);
    while (twoSidedP(hi, df) > alpha) hi *= 2;
    for (let i = 0; i < 200; i++) {
      const mid = (lo + hi) / 2;
      if (twoSidedP(mid, df) > alpha) lo = mid; else hi = mid;
      if (hi - lo < 1e-14 * hi) break;
    }
    return (lo + hi) / 2;
  }

  // ------------------------------------------------------------ record views

  function num(v) {
    if (v && typeof v === "object" && !Array.isArray(v)) v = v.value;
    if (v === null || v === undefined || typeof v === "boolean") return NaN;
    if (typeof v === "number") return v;
    if (typeof v === "string") return v === "NaN" ? NaN : v === "Inf" ? Infinity : v === "-Inf" ? -Infinity : NaN;
    return NaN;
  }

  function metricValue(v) {
    if (v && typeof v === "object" && !Array.isArray(v)) return "value" in v ? v.value : undefined;
    if (v === "NaN" || v === "Inf" || v === "-Inf") return num(v);
    return v;
  }

  function vcovs(rec) {
    const v = (rec.structures || {}).vcov;
    if (v === undefined || v === null) return [];
    return Array.isArray(v) ? v : [v];
  }

  function clusterList(v) {
    const cl = v.cluster || [];
    return typeof cl === "string" ? [cl] : cl;
  }

  function vcovLabel(v) {
    const cl = clusterList(v);
    return cl.length ? "by: " + cl.join(" & ") : String(v.type || "?");
  }

  function pickVcov(rec, sel) {
    const vs = vcovs(rec);
    if (sel === null || sel === undefined || sel === "") return vs.find((v) => v.default === true) || null;
    if (typeof sel === "number") {
      if (sel < 0 || sel >= vs.length) throw new Error(`the record has ${vs.length} vcov`);
      return vs[sel];
    }
    const hits = vs.filter((v) => [v.type, vcovLabel(v), clusterList(v).join(" & ")].includes(sel));
    if (!hits.length) throw new Error(`no vcov '${sel}'; the record has: ` + vs.map((v) => `${v.type} (${vcovLabel(v)})`).join(", "));
    if (hits.length > 1) throw new Error(`vcov '${sel}' matches ${hits.length} matrices; pick one by position`);
    return hits[0];
  }

  const PARAM = ["estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high"];

  function tidy(rec, opts) {
    opts = opts || {};
    const component = opts.component === undefined ? null : opts.component;
    const rows = [];
    for (const p of rec.parameters || []) {
      const comp = p.component === undefined ? null : p.component;
      if (component === null && comp !== null) continue;
      if (component !== null && component !== "all") {
        const want = Array.isArray(component) ? component : [component];
        if (!want.includes(comp)) continue;
      }
      if (p.dropped !== undefined && p.dropped !== null && !opts.dropped) continue;
      const row = { term: p.term };
      for (const k of ["response", "component", "dropped"]) if (p[k] !== undefined && p[k] !== null) row[k] = p[k];
      for (const k of PARAM) row[k] = num(p[k]);
      rows.push(row);
    }
    const sel = opts.vcov === undefined ? null : opts.vcov;
    const v = pickVcov(rec, sel);
    const recompute = sel !== null && sel !== "" && !(v || {}).default;
    let dft = num((v || {}).df_t);
    dft = Number.isNaN(dft) ? null : dft;
    if (recompute) {
      if (v.kind === "link") throw new Error(`this vcov is in attachment '${v.attachment}'`);
      const labels = v.labels || v.row_labels || [];
      const diag = new Map(labels.map((l, i) => [l, num(v.data[i][i])]));
      for (const r of rows) {
        const vv = diag.has(r.term) ? diag.get(r.term) : NaN;
        const se = vv >= 0 ? Math.sqrt(vv) : NaN;
        r.std_error = se;
        r.statistic = se ? r.estimate / se : NaN;
        r.p_value = twoSidedP(r.statistic, dft);
      }
    }
    const level = num((rec.metrics || {}).conf_level);
    const want = opts.confLevel !== undefined && opts.confLevel !== null ? opts.confLevel : Number.isNaN(level) ? 0.95 : level;
    if (recompute || Number.isNaN(level) || Math.abs(want - level) > 1e-12 || rows.every((r) => Number.isNaN(r.conf_low))) {
      const q = criticalValue(want, dft);
      for (const r of rows) {
        r.conf_low = r.estimate - q * r.std_error;
        r.conf_high = r.estimate + q * r.std_error;
      }
    }
    return rows;
  }

  function glance(rec, opts) {
    opts = opts || {};
    const which = opts.metrics || "table";
    let ms = {};
    for (const [k, v] of Object.entries(rec.metrics || {})) if (k !== "conf_level") ms[k] = v;
    if (which === "table") {
      if (!("rmse" in ms) && "rss" in ms && "nobs" in ms) {
        const n = num(ms.nobs);
        ms.rmse = n > 0 ? Math.sqrt(num(ms.rss) / n) : NaN;
      }
      const kept = {};
      for (const k of TABLE_METRICS) if (k in ms) kept[k] = ms[k];
      ms = kept;
    }
    const out = {};
    for (const [k, v] of Object.entries(ms)) {
      if (v && typeof v === "object" && !Array.isArray(v) && !("value" in v)) continue;
      out[k] = metricValue(v);
    }
    const v = pickVcov(rec, opts.vcov === undefined ? null : opts.vcov);
    if (v) out.vcov_type = vcovLabel(v);
    const fes = (rec.specification || {}).fixed_effects;
    if (fes && fes.length) out.fixed_effects = fes.slice();
    return out;
  }

  // ------------------------------------------------------------ canonical JSON and hashes

  // RFC 8785: ECMAScript number and string forms, keys sorted by UTF-16 code units
  function canonicalJSON(v) {
    if (v === null || typeof v !== "object") return JSON.stringify(v);
    if (Array.isArray(v)) return "[" + v.map(canonicalJSON).join(",") + "]";
    const keys = Object.keys(v).filter((k) => v[k] !== undefined).sort();
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalJSON(v[k])).join(",") + "}";
  }

  async function sha256Hex(text) {
    const subtle = (typeof crypto !== "undefined" && crypto.subtle) || (typeof require === "function" ? require("crypto").webcrypto.subtle : null);
    if (!subtle) return null;
    const buf = await subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  const recordSha256 = (rec) => sha256Hex(canonicalJSON(rec));

  // ------------------------------------------------------------ table specs

  function findTest(rec, key) {
    const tests = rec.tests || [];
    return tests.find((t) => t.label === key) || tests.find((t) => t.name === key) || null;
  }

  function fixed(x, digits) {
    if (x === null || x === undefined || Number.isNaN(x)) return "";
    if (!Number.isFinite(x)) return x > 0 ? "Inf" : "-Inf";
    let s = x.toFixed(digits);
    if (s.startsWith("-") && Number(s) === 0) s = s.slice(1);
    return s;
  }

  function statValue(x, digits, thousands) {
    if (x === null || x === undefined) return "";
    if (typeof x === "boolean") return x ? "Yes" : "No";
    if (typeof x === "string") return x;
    if (Number.isNaN(x)) return "";
    if (Number.isFinite(x) && Number.isInteger(x) && Math.abs(x) < 1e15) {
      const s = Math.abs(x).toString().replace(/\B(?=(\d{3})+(?!\d))/g, thousands);
      return (x < 0 ? "-" : "") + s;
    }
    return fixed(x, digits);
  }

  function pValue(p, digits, style) {
    if (p === null || p === undefined || Number.isNaN(p)) return "";
    if (style === "less_than" && p < 10 ** -digits) return "<" + fixed(10 ** -digits, digits);
    return fixed(p, digits);
  }

  function fill(template, row, digits, pDigits, pStyle, missing) {
    const vals = {};
    for (const m of template.matchAll(PLACEHOLDER)) {
      const x = row[m[1]];
      if (x === null || x === undefined || Number.isNaN(x)) return missing;
      vals[m[1]] = m[1] === "p_value" ? pValue(x, pDigits, pStyle) : fixed(x, digits);
    }
    return template.replace(PLACEHOLDER, (_, n) => vals[n]);
  }

  function starsFor(p, thresholds, symbols) {
    if (p === null || p === undefined || Number.isNaN(p)) return "";
    let out = "";
    thresholds.forEach((t, i) => { if (p < t) out = symbols[i]; });
    return out;
  }

  function issue(level, path, message) { return { level, path, message }; }

  // records: Map of meta.id -> {record, member, source}; also keyed "source\u0000id"
  function indexRecords(items) {
    const idx = new Map();
    for (const it of items) {
      const id = ((it.record || {}).meta || {}).id;
      if (!id) continue;
      if (it.source && !idx.has(it.source + "\u0000" + id)) idx.set(it.source + "\u0000" + id, it);
      if (!idx.has(id)) idx.set(id, it);
    }
    return idx;
  }

  function lookup(idx, col) {
    return (col.source && idx.get(col.source + "\u0000" + col.record)) || idx.get(col.record) || null;
  }

  function validateTable(spec, idx) {
    const out = [];
    if (spec.schema !== TABLE_SCHEMA) out.push(issue("error", "schema", `expected '${TABLE_SCHEMA}'`));
    const cols = Array.isArray(spec.columns) ? spec.columns : [];
    if (!cols.length) out.push(issue("error", "columns", "at least one column"));
    const ids = (spec.sources || []).map((s) => s.id);
    for (const d of new Set(ids.filter((x, i) => ids.indexOf(x) !== i))) out.push(issue("error", "sources", `duplicate source id '${d}'`));
    cols.forEach((c, i) => {
      if (!c || !c.record) out.push(issue("error", `columns[${i}]`, "a column needs `record` (a meta.id)"));
      else if (c.source !== undefined && c.source !== null && !ids.includes(c.source)) out.push(issue("error", `columns[${i}].source`, `no source '${c.source}'`));
    });
    for (const key of ["keep", "drop"]) {
      (spec[key] || []).forEach((p, j) => {
        try { new RegExp(p); } catch (e) { out.push(issue("error", `${key}[${j}]`, `pattern doesn't compile: ${e.message}`)); }
      });
    }
    out.push(...lineIssues(spec));
    (spec.stats || []).forEach((s, j) => {
      if (s.values && s.values.length !== cols.length) out.push(issue("error", `stats[${j}].values`, `${s.values.length} values for ${cols.length} columns`));
    });
    if (!idx) return out;
    const recs = [];
    cols.forEach((c, i) => {
      if (!c || !c.record) return;
      const f = lookup(idx, c);
      if (!f) { out.push(issue("error", `columns[${i}]`, `record ${c.record} not found`)); return; }
      recs.push(f.record);
      if (c.vcov !== undefined && c.vcov !== null) {
        try { pickVcov(f.record, c.vcov); } catch (e) { out.push(issue("warning", `columns[${i}].vcov`, e.message)); }
      }
    });
    const terms = new Set(recs.flatMap((r) => (r.parameters || []).map((p) => p.term)));
    (spec.rows || []).forEach((row, j) => {
      const names = row.terms || [row.term];
      if (!names.some((n) => terms.has(n))) out.push(issue("warning", `rows[${j}]`, `no column has ${names.join(", ")}`));
    });
    (spec.stats || []).forEach((s, j) => {
      if ("metric" in s) {
        const ok = recs.some((r) => s.metric in (r.metrics || {}) || (s.metric === "rmse" && "rss" in (r.metrics || {})));
        if (!ok) out.push(issue("warning", `stats[${j}]`, `no record has metric '${s.metric}'`));
      } else if ("fixed_effect" in s) {
        if (!recs.some((r) => ((r.specification || {}).fixed_effects || []).includes(s.fixed_effect))) out.push(issue("warning", `stats[${j}]`, `no record has fixed effect '${s.fixed_effect}'`));
      } else if ("test" in s) {
        if (!recs.some((r) => findTest(r, s.test))) out.push(issue("warning", `stats[${j}]`, `no record has test '${s.test}'`));
      }
    });
    return out;
  }

  // Check columns' sha256 pins (async: hashing)
  async function checkPins(spec, idx) {
    const out = [];
    for (const [i, c] of (spec.columns || []).entries()) {
      if (!c.sha256) continue;
      const f = lookup(idx, c);
      if (!f) continue;
      const h = await recordSha256(f.record);
      if (h && h !== c.sha256) out.push(issue("warning", `columns[${i}].sha256`, "the record has changed since the table was made"));
    }
    return out;
  }

  function buildTable(spec, idx) {
    const issues = validateTable(spec, idx);
    const errors = issues.filter((i) => i.level === "error");
    if (errors.length) throw new Error(errors.map((i) => `${i.path}: ${i.message}`).join("; "));
    const fmt = spec.format || {};
    const digits = fmt.digits !== undefined ? fmt.digits : 3;
    const thousands = fmt.thousands !== undefined ? fmt.thousands : ",";
    const missing = fmt.missing !== undefined ? fmt.missing : "";
    const stars = spec.stars || [];
    const symbols = fmt.star_symbols || stars.map((_, i) => "*".repeat(i + 1));
    const lines = uncertaintyLines(spec);
    const pDigits = fmt.p_digits !== undefined ? fmt.p_digits : digits;
    const pStyle = fmt.p_style || "fixed";

    const cols = spec.columns.map((c, i) => {
      const f = lookup(idx, c);
      let rows = tidy(f.record, { vcov: c.vcov, component: c.component });
      if (c.response) rows = rows.filter((r) => r.response === c.response);
      const header = c.header !== undefined ? c.header : (f.member || {}).label || (f.record.meta || {}).title || `(${i + 1})`;
      return { spec: c, found: f, tidy: new Map(rows.map((r) => [r.term, r])), order: rows.map((r) => r.term), header };
    });

    const listed = [];
    const taken = new Set();
    for (const row of spec.rows || []) {
      const names = row.terms || [row.term];
      listed.push([row.label || names[0], names]);
      names.forEach((n) => taken.add(n));
    }
    if (spec.keep_unlisted !== false) {
      const keep = (spec.keep || []).map((p) => new RegExp(p));
      const drop = (spec.drop || []).map((p) => new RegExp(p));
      const seen = [];
      for (const c of cols) {
        for (const t of c.order) {
          if (taken.has(t) || seen.includes(t)) continue;
          if (keep.length && !keep.some((k) => k.test(t))) continue;
          if (drop.some((d) => d.test(t))) continue;
          seen.push(t);
        }
      }
      for (const t of seen) listed.push([t, [t]]);
    }

    const rows = [];
    for (const [label, names] of listed) {
      const est = [];
      const below = lines.map(() => []);
      for (const c of cols) {
        const n = names.find((x) => c.tidy.has(x));
        const r = n === undefined ? null : c.tidy.get(n);
        if (!r) { est.push(missing); below.forEach((b) => b.push(missing)); continue; }
        est.push(fixed(r.estimate, digits) + starsFor(r.p_value, stars, symbols));
        lines.forEach((t, k) => below[k].push(fill(t, r, digits, pDigits, pStyle, missing)));
      }
      rows.push({ label, cells: est, kind: "estimate" });
      for (const b of below) rows.push({ label: "", cells: b, kind: "uncertainty" });
    }

    for (const s of spec.stats || []) {
      const d = s.digits !== undefined ? s.digits : digits;
      let cells = [], label;
      if ("values" in s) {
        cells = s.values.map(String);
        label = s.label;
      } else if ("metric" in s) {
        const m = s.metric;
        label = s.label || STAT_LABELS[m] || m;
        for (const c of cols) {
          const g = glance(c.found.record, { vcov: c.spec.vcov, metrics: "all" });
          if (m === "rmse" && !("rmse" in g)) g.rmse = glance(c.found.record, { metrics: "table" }).rmse;
          const v = g[m];
          cells.push(v === undefined || v === null ? missing : statValue(v, d, thousands));
        }
      } else if ("vcov" in s) {
        label = s.label || (s.vcov === "type" ? "Std. errors" : "Clusters");
        for (const c of cols) {
          const v = pickVcov(c.found.record, c.spec.vcov);
          if (!v) cells.push(missing);
          else if (s.vcov === "type") cells.push(vcovLabel(v));
          else {
            const n = v.n_clusters && typeof v.n_clusters === "object" ? Object.values(v.n_clusters) : [];
            cells.push(n.map((x) => statValue(x, 0, thousands)).join(" / ") || missing);
          }
        }
      } else if ("fixed_effect" in s) {
        label = s.label || `FE: ${s.fixed_effect}`;
        const yes = fmt.fe_yes !== undefined ? fmt.fe_yes : "Yes", no = fmt.fe_no !== undefined ? fmt.fe_no : "";
        for (const c of cols) cells.push(((c.found.record.specification || {}).fixed_effects || []).includes(s.fixed_effect) ? yes : no);
      } else if ("test" in s) {
        label = s.label || s.test;
        const which = s.value || "statistic";
        for (const c of cols) {
          const t = findTest(c.found.record, s.test);
          const v = t ? num(t[which]) : NaN;
          if (Number.isNaN(v)) cells.push(missing);
          else if (which === "p_value") cells.push(pValue(v, s.digits !== undefined ? s.digits : pDigits, pStyle));
          else cells.push(fixed(v, d));
        }
      }
      rows.push({ label, cells, kind: "stat" });
    }

    const notes = (spec.notes || []).slice();
    if (stars.length) notes.push(stars.map((t, i) => `${symbols[i]} p < ${t}`).join(", "));
    const note = uncertaintyNote(spec, lines);
    if (note) notes.push(note);
    return {
      title: spec.title === undefined ? null : spec.title,
      header: cols.map((c) => c.header),
      rows,
      notes,
      warnings: issues.filter((i) => i.level === "warning").map((i) => `warning: ${i.path}: ${i.message}`),
    };
  }

  // ------------------------------------------------------------ rendering

  const LATEX = { "&": "\\&", "%": "\\%", $: "\\$", "#": "\\#", _: "\\_", "{": "\\{", "}": "\\}", "~": "\\textasciitilde{}", "^": "\\textasciicircum{}", "\\": "\\textbackslash{}" };
  const tex = (s) => Array.from(String(s)).map((ch) => LATEX[ch] || ch).join("");
  const escHTML = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#x27;");

  function renderMarkdown(t) {
    const esc = (s) => String(s).replace(/\\/g, "\\\\").replace(/\|/g, "\\|").replace(/\*/g, "\\*");
    const lines = [];
    if (t.title) lines.push(`**${esc(t.title)}**`, "");
    lines.push("| | " + t.header.map(esc).join(" | ") + " |");
    lines.push("|---|" + "---:|".repeat(t.header.length));
    for (const r of t.rows) lines.push(`| ${esc(r.label)} | ` + r.cells.map(esc).join(" | ") + " |");
    if (t.notes.length) lines.push("", ...t.notes.map((n) => `${esc(n)}  `));
    return lines.join("\n").replace(/\s+$/, "") + "\n";
  }

  function renderLatex(t, opts) {
    const e = opts && opts.escape === false ? (s) => String(s) : tex;
    const n = t.header.length;
    const lines = ["\\begin{table}[htbp]", "\\centering"];
    if (t.title) lines.push(`\\caption{${e(t.title)}}`);
    lines.push(`\\begin{tabular}{l${"c".repeat(n)}}`, "\\toprule");
    lines.push(" & " + t.header.map(e).join(" & ") + " \\\\");
    lines.push("\\midrule");
    let prev = null;
    for (const r of t.rows) {
      if (r.kind === "stat" && prev !== "stat") lines.push("\\midrule");
      lines.push(`${e(r.label)} & ` + r.cells.map(e).join(" & ") + " \\\\");
      prev = r.kind;
    }
    lines.push("\\bottomrule", "\\end{tabular}");
    if (t.notes.length) lines.push("\\par\\smallskip{\\footnotesize " + t.notes.map(e).join(" ") + "}");
    lines.push("\\end{table}");
    return lines.join("\n") + "\n";
  }

  function renderHTML(t) {
    const h = escHTML;
    const out = ['<table class="estimation-table">'];
    if (t.title) out.push(`<caption>${h(t.title)}</caption>`);
    out.push("<thead><tr><th></th>" + t.header.map((x) => `<th>${h(x)}</th>`).join("") + "</tr></thead>");
    out.push("<tbody>");
    let prev = null;
    for (const r of t.rows) {
      const cls = r.kind + (r.kind === "stat" && prev !== "stat" ? " first-stat" : "");
      out.push(`<tr class="${cls}"><th>${h(r.label)}</th>` + r.cells.map((x) => `<td>${h(x)}</td>`).join("") + "</tr>");
      prev = r.kind;
    }
    out.push("</tbody>");
    if (t.notes.length) out.push(`<tfoot><tr><td colspan="${t.header.length + 1}">` + t.notes.map(h).join("<br>") + "</td></tr></tfoot>");
    out.push("</table>");
    return out.join("\n") + "\n";
  }

  function renderCSV(t) {
    const q = (s) => (/[",\n\r]/.test(s) ? `"${String(s).replace(/"/g, '""')}"` : String(s));
    const lines = [["", ...t.header].map(q).join(",")];
    for (const r of t.rows) lines.push([r.label, ...r.cells].map(q).join(","));
    return lines.join("\n") + "\n";
  }

  function renderText(t) {
    const rows = [["", ...t.header], ...t.rows.map((r) => [r.label, ...r.cells])];
    const widths = rows[0].map((_, i) => Math.max(...rows.map((r) => r[i].length)));
    const line = (r) => r.map((c, i) => (i === 0 ? c.padEnd(widths[0]) : c.padStart(widths[i]))).join("  ").replace(/\s+$/, "");
    const rule = widths.map((w) => "-".repeat(w)).join("  ");
    const out = [];
    if (t.title) out.push(t.title);
    out.push(line(rows[0]), rule);
    let prev = null;
    t.rows.forEach((src, i) => {
      if (src.kind === "stat" && prev !== "stat") out.push(rule);
      out.push(line(rows[i + 1]));
      prev = src.kind;
    });
    out.push(rule, ...t.notes);
    return out.join("\n") + "\n";
  }

  const RENDERERS = { text: renderText, markdown: renderMarkdown, latex: renderLatex, html: renderHTML, csv: renderCSV };

  function render(t, format, opts) {
    const f = RENDERERS[format || "text"];
    if (!f) throw new Error("format is one of " + Object.keys(RENDERERS).join(", "));
    return f(t, opts);
  }

  // ------------------------------------------------------------ reading files

  // A parsed JSON document -> [{record, member}] (a record, or a collection's members). Members
  // in a members file are looked up in `jsonl` (a map from file name to its text).
  function recordsIn(doc, jsonl) {
    if (doc && doc.schema === "estimation/0.1") return { items: [{ record: doc, member: null }], missing: [] };
    if (doc && typeof doc.schema === "string" && doc.schema.startsWith("estimation-collection/")) {
      const items = [], missing = [];
      const files = new Map();
      const atts = new Map((doc.attachments || []).map((a) => [a.id, a]));
      for (const m of doc.members || []) {
        let rec = m.record;
        if (!rec && m.attachment) {
          const att = atts.get(m.attachment);
          const name = att && att.path ? att.path.split("/").pop() : null;
          if (name && jsonl && jsonl.has(name)) {
            if (!files.has(name)) {
              const byId = new Map();
              for (const ln of jsonl.get(name).split(/\r?\n/)) if (ln.trim()) { const r = JSON.parse(ln); byId.set((r.meta || {}).id, r); }
              files.set(name, byId);
            }
            rec = files.get(name).get(m.id);
          } else if (name && !missing.includes(name)) missing.push(name);
        }
        if (rec) {
          const member = Object.assign({}, m);
          delete member.record;
          items.push({ record: rec, member });
        }
      }
      return { items, missing };
    }
    return null;
  }

  function newSpec(items, opts) {
    opts = opts || {};
    const uuid = typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : "00000000-0000-4000-8000-" + String(Date.now()).padStart(12, "0").slice(-12);
    const spec = {
      schema: TABLE_SCHEMA,
      meta: { id: uuid, created: new Date().toISOString().replace(/\.\d+Z$/, "Z"), producer: { name: "estimation viewer", version: "0.1" } },
      columns: items.map((it, i) => ({ record: it.record.meta.id, header: (it.member || {}).label || `(${i + 1})` })),
      uncertainty: "std_error",
      stars: DEFAULT_STARS.slice(),
      stats: [{ metric: "nobs" }, { metric: "r2" }, { vcov: "type" }],
    };
    return Object.assign(spec, opts);
  }

  return {
    TABLE_SCHEMA, DEFAULT_STARS, TABLE_METRICS, STAT_LABELS,
    twoSidedP, criticalValue, erfc, qnorm,
    NAMED_LINES, PLACEHOLDERS, uncertaintyLines, pValue,
    num, vcovs, vcovLabel, pickVcov, tidy, glance, findTest,
    canonicalJSON, sha256Hex, recordSha256,
    indexRecords, validateTable, checkPins, buildTable, render, renderers: RENDERERS,
    recordsIn, newSpec, fixed, statValue,
  };
});

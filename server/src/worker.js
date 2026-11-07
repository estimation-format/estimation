// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ted Matherly and the estrec contributors
//
// estrec.org: one Cloudflare Worker serves the static site (spec links, schemas at their $ids,
// the viewer) and the Publish service.
//
//   POST   /api/publish     {spec, records, licence, turnstile} -> {id, url, data_url, delete_token}
//   GET    /t/<id>          the table as a web page (the viewer's web export, rendered here)
//   GET    /t/<id>/data     the stored spec and records as JSON
//   DELETE /api/t/<id>      Authorization: Bearer <delete token>
//   POST   /api/report      {id, reason}: kept in the bucket for review
//   GET    /api/config      {turnstile_sitekey, licences, limits} for the viewer
//
// Only data is stored, never HTML: a table spec (estrec-table/0.1) and the records behind its
// columns (estrec/0.1), with identifying fields removed here whatever the client did. Pages are
// rendered from that data by one fixed template under a CSP that allows only the template's
// own script (by hash), so stored content can't run code. Published tables are unlisted
// (random ids, noindex) and expire a year after they were last viewed.

import E from "../../viewer/estrec-table.js";
import IDENTIFYING from "../../viewer/identifying.js";

export const LICENCES = {
  "CC0-1.0": { name: "CC0 1.0", url: "https://creativecommons.org/publicdomain/zero/1.0/" },
  "CC-BY-4.0": { name: "CC BY 4.0", url: "https://creativecommons.org/licenses/by/4.0/" },
  "CC-BY-SA-4.0": { name: "CC BY-SA 4.0", url: "https://creativecommons.org/licenses/by-sa/4.0/" },
};
export const DEFAULT_LICENCE = "CC0-1.0";
export const LIMITS = { bytes: 2 * 1024 * 1024, records: 50, columns: 50, report_bytes: 4096 };
export const EXPIRE_DAYS = 365;
const RECORD_SCHEMA = "estrec/0.1";
const PUBLISHER = { name: "estrec.org publish", version: "0.1" };
const ID = /^[A-Za-z0-9_-]{22}$/;

const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Strict-Transport-Security": "max-age=31536000",
};
// The viewer reads files in the browser and talks only to this origin (and Turnstile)
const SITE_CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' https://challenges.cloudflare.com",
  "frame-src https://challenges.cloudflare.com",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src https://fonts.gstatic.com",
  "img-src 'self' data: blob:",
  "connect-src 'self'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
].join("; ");

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ------------------------------------------------------------------ helpers

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}

function withHeaders(res, headers) {
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(headers)) if (!out.headers.has(k)) out.headers.set(k, v);
  return out;
}

function b64url(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomToken(n) {
  return b64url(crypto.getRandomValues(new Uint8Array(n)));
}

async function sha256(text, encoding = "hex") {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  if (encoding === "base64") return btoa(String.fromCharCode(...d));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let x = 0;
  for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function today(now) {
  return new Date(now).toISOString().slice(0, 10);
}

function daysBetween(a, b) {
  return Math.floor((Date.parse(b) - Date.parse(a)) / 86400000);
}

async function readBody(request, limit) {
  const declared = Number(request.headers.get("Content-Length") || 0);
  if (declared > limit) throw new HttpError(413, `the upload is larger than ${limit} bytes`);
  const buf = await request.arrayBuffer();
  if (buf.byteLength > limit) throw new HttpError(413, `the upload is larger than ${limit} bytes`);
  try {
    return JSON.parse(new TextDecoder().decode(buf));
  } catch {
    throw new HttpError(400, "the body isn't JSON");
  }
}

// ------------------------------------------------------------------ checking a submission

// The spec and the records as they will be stored: records checked, unused ones dropped,
// identifying fields removed, local source paths dropped, sha256 pins renewed (redaction
// changes the records they pinned).
export async function prepare(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new HttpError(400, "expected {spec, records}");
  const { spec, records } = body;
  const licence = body.licence === undefined ? DEFAULT_LICENCE : body.licence;
  if (!Object.hasOwn(LICENCES, licence)) {
    throw new HttpError(400, `licence must be one of ${Object.keys(LICENCES).join(", ")}`);
  }
  if (!spec || typeof spec !== "object" || Array.isArray(spec)) throw new HttpError(400, "spec: expected a table spec");
  if (spec.schema !== E.TABLE_SCHEMA) throw new HttpError(400, `spec.schema: expected '${E.TABLE_SCHEMA}'`);
  if (!Array.isArray(spec.columns) || spec.columns.length > LIMITS.columns) {
    throw new HttpError(400, `spec.columns: 1 to ${LIMITS.columns} columns`);
  }
  if (!Array.isArray(records) || !records.length || records.length > LIMITS.records) {
    throw new HttpError(400, `records: 1 to ${LIMITS.records} records`);
  }
  const byId = new Map();
  records.forEach((r, i) => {
    if (!r || typeof r !== "object" || Array.isArray(r)) throw new HttpError(400, `records[${i}]: expected a record`);
    if (r.schema !== RECORD_SCHEMA) throw new HttpError(400, `records[${i}].schema: expected '${RECORD_SCHEMA}'`);
    const id = (r.meta || {}).id;
    if (typeof id !== "string" || !id) throw new HttpError(400, `records[${i}].meta.id: missing`);
    if (byId.has(id) && JSON.stringify(byId.get(id)) !== JSON.stringify(r)) {
      throw new HttpError(400, `records[${i}]: two different records with id ${id}`);
    }
    byId.set(id, r);
  });
  const cols = spec.columns.map((c, i) => {
    if (!c || typeof c !== "object" || typeof c.record !== "string") {
      throw new HttpError(400, `spec.columns[${i}].record: missing`);
    }
    if (!byId.has(c.record)) throw new HttpError(400, `spec.columns[${i}]: record ${c.record} isn't in records`);
    return c;
  });

  const used = [...new Set(cols.map((c) => c.record))];
  const clean = new Map();
  for (const id of used) clean.set(id, E.redactRecord(byId.get(id), IDENTIFYING, PUBLISHER).record);
  const out = JSON.parse(JSON.stringify(spec));
  delete out.sources; // local paths, and not needed: every column's record is stored
  for (const c of out.columns) {
    delete c.source;
    if (c.sha256) c.sha256 = await E.recordSha256(clean.get(c.record));
  }
  const kept = [...clean.values()];
  try {
    E.buildTable(out, E.indexRecords(kept.map((record) => ({ record }))));
  } catch (e) {
    throw new HttpError(400, `the table can't be built: ${e.message}`);
  }
  return { spec: out, records: kept, licence };
}

// ------------------------------------------------------------------ rendering

const INLINE_SCRIPT = /<script>([\s\S]*?)<\/script>/g;

export async function renderPage(doc, id, now) {
  const built = E.buildTable(doc.spec, E.indexRecords(doc.records.map((record) => ({ record }))));
  const lic = LICENCES[doc.licence] || LICENCES[DEFAULT_LICENCE];
  const expires = new Date(Date.parse(doc.accessed || today(now)) + EXPIRE_DAYS * 86400000).toISOString().slice(0, 10);
  const footer =
    '<footer style="max-width:860px;margin:28px auto 0;color:var(--muted);font:12px/1.5 system-ui,sans-serif;text-align:center">' +
    `Published ${esc((doc.created || "").slice(0, 10))} with <a href="/" style="color:inherit">estrec</a> · ` +
    `Licence: <a href="${esc(lic.url)}" rel="license" style="color:inherit">${esc(lic.name)}</a> · ` +
    `<a href="/t/${esc(id)}/data" style="color:inherit">Data (JSON)</a> · ` +
    `<a href="/report.html#${esc(id)}" style="color:inherit">Report</a><br>` +
    `Unlisted. Kept until ${esc(expires)}, a year after its last view.</footer>\n`;
  const html = E.renderWebPage(built, doc.records).replace("</body>", footer + "</body>");
  const hashes = [];
  for (const m of html.matchAll(INLINE_SCRIPT)) hashes.push(`'sha256-${await sha256(m[1], "base64")}'`);
  const csp = [
    "default-src 'none'",
    `script-src ${hashes.join(" ") || "'none'"}`,
    "style-src 'unsafe-inline'",
    "img-src data:",
    "base-uri 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
  return { html, csp };
}

// ------------------------------------------------------------------ storage

const key = (id) => `t/${id}.json`;

async function load(env, id, now, ctx) {
  const obj = await env.BUCKET.get(key(id));
  if (!obj) return null;
  const doc = JSON.parse(await obj.text());
  const day = today(now);
  if (doc.accessed && daysBetween(doc.accessed, day) > EXPIRE_DAYS) {
    ctx.waitUntil(env.BUCKET.delete(key(id)));
    return null;
  }
  if (doc.accessed !== day) {
    // At most one write per table per day; rewriting also restarts the bucket's age-based
    // lifecycle rule, so that rule expires tables a year after their last view
    doc.accessed = day;
    ctx.waitUntil(env.BUCKET.put(key(id), JSON.stringify(doc), { httpMetadata: { contentType: "application/json" } }));
  }
  return doc;
}

async function verifyTurnstile(env, token, ip, fetcher) {
  if (!env.TURNSTILE_SECRET) return; // local development only; deployed, the secret is set
  if (typeof token !== "string" || !token) throw new HttpError(403, "the Turnstile check is missing");
  const form = new FormData();
  form.append("secret", env.TURNSTILE_SECRET);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const res = await fetcher("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
  const out = await res.json().catch(() => ({}));
  if (!out.success) throw new HttpError(403, "the Turnstile check failed; try again");
}

async function limit(binding, ip) {
  if (!binding) return;
  const { success } = await binding.limit({ key: ip || "unknown" });
  if (!success) throw new HttpError(429, "too many requests; try again in a minute");
}

// ------------------------------------------------------------------ routes

async function publish(request, env, deps) {
  const ip = request.headers.get("CF-Connecting-IP") || "";
  await limit(env.PUBLISH_LIMITER, ip);
  const body = await readBody(request, LIMITS.bytes);
  await verifyTurnstile(env, body && body.turnstile, ip, deps.fetch);
  const doc = await prepare(body);
  const id = randomToken(16);
  const token = randomToken(32);
  const day = today(deps.now());
  const stored = {
    v: 1,
    ...doc,
    created: new Date(deps.now()).toISOString().replace(/\.\d+Z$/, "Z"),
    accessed: day,
    delete_sha256: await sha256(token),
  };
  await env.BUCKET.put(key(id), JSON.stringify(stored), { httpMetadata: { contentType: "application/json" } });
  const origin = new URL(request.url).origin;
  return json(
    {
      id,
      url: `${origin}/t/${id}`,
      data_url: `${origin}/t/${id}/data`,
      delete_url: `${origin}/delete.html#${id}.${token}`,
      delete_token: token,
      licence: doc.licence,
      removed_identifying: true,
      expires: `a year after the last view (now ${today(Date.parse(day) + EXPIRE_DAYS * 86400000)})`,
    },
    201,
  );
}

async function remove(request, env, id) {
  const auth = request.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const obj = await env.BUCKET.get(key(id));
  if (!obj) throw new HttpError(404, "no such table");
  const doc = JSON.parse(await obj.text());
  if (!token || !safeEqual(await sha256(token), doc.delete_sha256)) throw new HttpError(403, "wrong delete token");
  await env.BUCKET.delete(key(id));
  return new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
}

async function report(request, env, deps) {
  await limit(env.REPORT_LIMITER, request.headers.get("CF-Connecting-IP") || "");
  const body = await readBody(request, LIMITS.report_bytes);
  const id = body && body.id;
  if (typeof id !== "string" || !ID.test(id)) throw new HttpError(400, "id: expected a published table's id");
  const reason = typeof body.reason === "string" ? body.reason.slice(0, 2000) : "";
  if (!reason.trim()) throw new HttpError(400, "reason: say what is wrong");
  const when = new Date(deps.now()).toISOString();
  await env.BUCKET.put(`reports/${id}/${when}-${randomToken(4)}.json`, JSON.stringify({ id, reason, when }), {
    httpMetadata: { contentType: "application/json" },
  });
  return json({ ok: true }, 202);
}

export async function handle(request, env, ctx, deps = {}) {
  deps = { fetch: (...a) => fetch(...a), now: () => Date.now(), ...deps };
  const url = new URL(request.url);
  const canonical = env.CANONICAL_HOST || "estrec.org";
  if (env.REDIRECT_HOSTS && env.REDIRECT_HOSTS.split(",").map((h) => h.trim()).includes(url.hostname)) {
    return Response.redirect(`https://${canonical}${url.pathname}${url.search}`, 301);
  }
  const path = url.pathname;
  const m = path.match(/^\/t\/([A-Za-z0-9_-]+)(\/data)?\/?$/);
  try {
    if (path === "/api/config" && request.method === "GET") {
      return json({ turnstile_sitekey: env.TURNSTILE_SITEKEY || null, licences: LICENCES, default_licence: DEFAULT_LICENCE, limits: LIMITS });
    }
    if (path === "/api/publish") {
      if (request.method !== "POST") throw new HttpError(405, "POST a table spec and its records");
      return withHeaders(await publish(request, env, deps), SECURITY);
    }
    if (path === "/api/report") {
      if (request.method !== "POST") throw new HttpError(405, "POST {id, reason}");
      return withHeaders(await report(request, env, deps), SECURITY);
    }
    const del = path.match(/^\/api\/t\/([A-Za-z0-9_-]+)$/);
    if (del) {
      if (request.method !== "DELETE") throw new HttpError(405, "DELETE with the delete token");
      if (!ID.test(del[1])) throw new HttpError(404, "no such table");
      return withHeaders(await remove(request, env, del[1]), SECURITY);
    }
    if (path.startsWith("/api/")) throw new HttpError(404, "no such endpoint");
    if (m) {
      if (request.method !== "GET" && request.method !== "HEAD") throw new HttpError(405, "GET only");
      const doc = ID.test(m[1]) ? await load(env, m[1], deps.now(), ctx) : null;
      const page = { ...SECURITY, "X-Robots-Tag": "noindex, nofollow", "Cache-Control": "public, max-age=300" };
      if (!doc) {
        return new Response("This table doesn't exist: it was deleted, or not viewed for a year.\n", {
          status: 404,
          headers: { ...page, "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
        });
      }
      if (m[2]) {
        const { spec, records, licence, created } = doc;
        return new Response(JSON.stringify({ spec, records, licence, created }, null, 1), {
          headers: { ...page, "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" },
        });
      }
      const { html, csp } = await renderPage(doc, m[1], deps.now());
      return new Response(request.method === "HEAD" ? null : html, {
        headers: { ...page, "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp },
      });
    }
    // The static site
    const res = await env.ASSETS.fetch(request);
    const extra = { ...SECURITY };
    if (path.startsWith("/schema/")) {
      extra["Access-Control-Allow-Origin"] = "*"; // validators and editors fetch schemas by $id
    } else {
      extra["Content-Security-Policy"] = SITE_CSP;
      extra["X-Frame-Options"] = "DENY";
    }
    return withHeaders(res, extra);
  } catch (e) {
    if (e instanceof HttpError) return withHeaders(json({ error: e.message }, e.status), SECURITY);
    console.error(e);
    return withHeaders(json({ error: "internal error" }, 500), SECURITY);
  }
}

export default {
  fetch(request, env, ctx) {
    return handle(request, env, ctx);
  },
};

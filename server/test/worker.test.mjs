// Tests for the estrec.org Worker: node --test server/test/
// An in-memory bucket stands in for R2; Turnstile and the rate limiters are mocked.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { EXPIRE_DAYS, handle, LIMITS } from "../src/worker.js";

const here = dirname(fileURLToPath(import.meta.url));
const examples = join(here, "..", "..", "schema", "examples");
const read = (name) => JSON.parse(readFileSync(join(examples, name), "utf8"));
const DAY = 86400000;
const T0 = Date.parse("2026-11-06T12:00:00Z");

class Bucket {
  constructor() { this.m = new Map(); }
  async get(k) { return this.m.has(k) ? { text: async () => this.m.get(k) } : null; }
  async put(k, v) { this.m.set(k, String(v)); }
  async delete(k) { this.m.delete(k); }
}

function setup(over = {}) {
  const pending = [];
  const env = {
    BUCKET: new Bucket(),
    ASSETS: { fetch: async () => new Response("<!doctype html><p>static</p>", { headers: { "Content-Type": "text/html" } }) },
    CANONICAL_HOST: "estrec.org",
    REDIRECT_HOSTS: "www.estrec.org,estimation-record.org,www.estimation-record.org",
    ...over,
  };
  const ctx = { waitUntil: (p) => pending.push(p) };
  let now = T0;
  const deps = { now: () => now, fetch: over.fetch };
  const call = async (path, init = {}, host = "estrec.org") => {
    const res = await handle(new Request(`https://${host}${path}`, init), env, ctx, deps);
    await Promise.all(pending.splice(0));
    return res;
  };
  return { env, call, setNow: (t) => { now = t; } };
}

// The example table and the records behind it (a collection's members), with identifying fields
function payload() {
  const spec = read("paper.estrec-table.json");
  const coll = read("paper.estrec-collection.json");
  const records = coll.members.map((m) => structuredClone(m.record));
  const prov = (records[0].provenance = records[0].provenance || {});
  prov.environment = { ...(prov.environment || {}), hostname: "laptop.local" };
  prov.execution = { ...(prov.execution || {}), invocation: { working_directory: "/home/ted/paper" } };
  return { spec, records };
}

const post = (body) => ({ method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

async function publish(call, body = payload()) {
  const res = await call("/api/publish", post(body));
  return { res, out: await res.json() };
}

test("publish stores data only, redacted, and returns an unlisted link and a delete token", async () => {
  const { env, call } = setup();
  const { res, out } = await publish(call);
  assert.equal(res.status, 201, JSON.stringify(out));
  assert.match(out.id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(out.url, `https://estrec.org/t/${out.id}`);
  assert.equal(out.delete_url, `https://estrec.org/delete.html#${out.id}.${out.delete_token}`);
  assert.equal(out.licence, "CC0-1.0");
  const stored = JSON.parse(env.BUCKET.m.get(`t/${out.id}.json`));
  assert.deepEqual(Object.keys(stored).sort(), ["accessed", "created", "delete_sha256", "licence", "records", "spec", "v"]);
  assert.equal(stored.delete_sha256, createHash("sha256").update(out.delete_token).digest("hex"));
  assert.ok(!JSON.stringify(stored).includes(out.delete_token), "the token itself isn't stored");
  assert.equal(stored.records[0].provenance.environment.hostname, undefined, "identifying fields removed");
  assert.ok(!JSON.stringify(stored).includes("/home/ted"));
  assert.equal(stored.records[0].history.at(-1).action, "redacted");
  assert.equal(stored.spec.sources, undefined, "local source paths dropped");
  assert.ok(stored.spec.columns.every((c) => c.source === undefined));
});

test("the page renders the table under a CSP that allows only its own script", async () => {
  const { call } = setup();
  const { out } = await publish(call);
  const res = await call(`/t/${out.id}`);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /<table class="estrec-table">/);
  assert.match(html, /CC0 1\.0/);
  assert.equal(res.headers.get("X-Robots-Tag"), "noindex, nofollow");
  const csp = res.headers.get("Content-Security-Policy");
  assert.match(csp, /default-src 'none'/);
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  assert.equal(scripts.length, 1);
  const hash = createHash("sha256").update(scripts[0]).digest("base64");
  assert.ok(csp.includes(`'sha256-${hash}'`), csp);
  assert.doesNotMatch(csp, /script-src[^;]*unsafe-inline/);
  const data = await (await call(`/t/${out.id}/data`)).json();
  assert.deepEqual(Object.keys(data).sort(), ["created", "licence", "records", "spec"]);
});

test("record text can't inject markup or script", async () => {
  const { call } = setup();
  const body = payload();
  const evil = '</script><script>alert(1)</script><img src=x onerror=alert(2)>';
  body.records[0].meta.title = evil;
  body.spec.title = evil;
  body.spec.columns[0].header = evil;
  const { res, out } = await publish(call, body);
  assert.equal(res.status, 201, JSON.stringify(out));
  const html = await (await call(`/t/${out.id}`)).text();
  assert.ok(!html.includes("<script>alert(1)"), "no raw script from the data");
  assert.ok(!html.includes("<img src=x"), "no raw markup from the data");
  assert.equal([...html.matchAll(/<script>/g)].length, 1);
});

test("bad submissions are refused with a reason", async () => {
  const { call } = setup();
  const cases = [
    [{ ...payload(), licence: "CC-BY-NC-4.0" }, 400, /licence/],
    [{ ...payload(), spec: { ...payload().spec, schema: "estimation-table/0.1" } }, 400, /spec.schema/],
    [{ spec: payload().spec, records: [] }, 400, /records/],
    [{ spec: payload().spec, records: payload().records.map((r) => ({ ...r, schema: "estimation/0.1" })) }, 400, /records\[0\].schema/],
    [{ spec: payload().spec, records: payload().records.slice(1) }, 400, /isn't in records/],
  ];
  for (const [body, status, re] of cases) {
    const { res, out } = await publish(call, body);
    assert.equal(res.status, status, JSON.stringify(out));
    assert.match(out.error, re);
  }
  const big = await call("/api/publish", post({ ...payload(), pad: "x".repeat(LIMITS.bytes) }));
  assert.equal(big.status, 413);
  const notJson = await call("/api/publish", { method: "POST", body: "{" });
  assert.equal(notJson.status, 400);
  assert.equal((await call("/api/publish")).status, 405);
});

test("licences: CC BY and CC BY-SA are offered, others refused", async () => {
  const { call } = setup();
  for (const lic of ["CC-BY-4.0", "CC-BY-SA-4.0"]) {
    const { res, out } = await publish(call, { ...payload(), licence: lic });
    assert.equal(res.status, 201);
    assert.equal(out.licence, lic);
  }
  const cfg = await (await call("/api/config")).json();
  assert.deepEqual(Object.keys(cfg.licences), ["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0"]);
  assert.equal(cfg.default_licence, "CC0-1.0");
});

test("delete needs the token", async () => {
  const { call } = setup();
  const { out } = await publish(call);
  const del = (tok) => call(`/api/t/${out.id}`, { method: "DELETE", headers: tok ? { Authorization: `Bearer ${tok}` } : {} });
  assert.equal((await del()).status, 403);
  assert.equal((await del("x".repeat(43))).status, 403);
  assert.equal((await del(out.delete_token)).status, 204);
  assert.equal((await call(`/t/${out.id}`)).status, 404);
  assert.equal((await del(out.delete_token)).status, 404);
});

test("a view renews the year; a year without one expires the table", async () => {
  const { env, call, setNow } = setup();
  const { out } = await publish(call);
  const k = `t/${out.id}.json`;
  setNow(T0 + 200 * DAY);
  assert.equal((await call(`/t/${out.id}`)).status, 200);
  assert.equal(JSON.parse(env.BUCKET.m.get(k)).accessed, new Date(T0 + 200 * DAY).toISOString().slice(0, 10));
  setNow(T0 + (200 + EXPIRE_DAYS) * DAY);
  assert.equal((await call(`/t/${out.id}`)).status, 200, "exactly a year after the last view: still there");
  setNow(T0 + (201 + 2 * EXPIRE_DAYS) * DAY);
  assert.equal((await call(`/t/${out.id}`)).status, 404);
  assert.equal(env.BUCKET.m.has(k), false, "and removed from the bucket");
});

test("one write per day at most for views", async () => {
  const { env, call } = setup();
  const { out } = await publish(call);
  let puts = 0;
  const put = env.BUCKET.put.bind(env.BUCKET);
  env.BUCKET.put = async (...a) => { puts++; return put(...a); };
  for (let i = 0; i < 3; i++) assert.equal((await call(`/t/${out.id}`)).status, 200);
  assert.equal(puts, 0, "same day as publishing: no rewrite");
});

test("Turnstile is checked when the secret is set", async () => {
  let seen = null;
  const fetch = async (url, init) => {
    seen = Object.fromEntries(init.body.entries());
    return new Response(JSON.stringify({ success: seen.response === "good" }));
  };
  const { call } = setup({ TURNSTILE_SECRET: "s3cret", fetch });
  assert.equal((await publish(call, payload())).res.status, 403);
  assert.equal((await publish(call, { ...payload(), turnstile: "bad" })).res.status, 403);
  assert.equal(seen.secret, "s3cret");
  assert.equal((await publish(call, { ...payload(), turnstile: "good" })).res.status, 201);
});

test("rate limits answer 429", async () => {
  const { call } = setup({ PUBLISH_LIMITER: { limit: async () => ({ success: false }) } });
  assert.equal((await publish(call)).res.status, 429);
});

test("reports are kept for review", async () => {
  const { env, call } = setup();
  const { out } = await publish(call);
  assert.equal((await call("/api/report", post({ id: out.id, reason: "" }))).status, 400);
  assert.equal((await call("/api/report", post({ id: "nope", reason: "x" }))).status, 400);
  assert.equal((await call("/api/report", post({ id: out.id, reason: "has a name in it" }))).status, 202);
  const keys = [...env.BUCKET.m.keys()].filter((k) => k.startsWith(`reports/${out.id}/`));
  assert.equal(keys.length, 1);
});

test("static files get headers; the other domains redirect", async () => {
  const { call } = setup();
  const page = await call("/viewer/");
  assert.match(page.headers.get("Content-Security-Policy"), /challenges\.cloudflare\.com/);
  assert.equal(page.headers.get("X-Content-Type-Options"), "nosniff");
  const schema = await call("/schema/estrec-0.1.json");
  assert.equal(schema.headers.get("Access-Control-Allow-Origin"), "*");
  for (const host of ["estimation-record.org", "www.estrec.org"]) {
    const r = await call("/schema/catalog.json?x=1", {}, host);
    assert.equal(r.status, 301);
    assert.equal(r.headers.get("Location"), "https://estrec.org/schema/catalog.json?x=1");
  }
  assert.equal((await call("/t/short")).status, 404);
  assert.equal((await call("/api/nothing")).status, 404);
});

// Used by tests/test_viewer.py: reads {files, sources, specs, pvals} as JSON on stdin and prints
// the viewer's tables and p-values, built by viewer/estimation-table.js, as JSON.
const E = require("../viewer/estimation-table.js");
let input = "";
process.stdin.on("data", (d) => (input += d));
process.stdin.on("end", async () => {
  const req = JSON.parse(input);
  const jsonl = new Map(req.files.filter((f) => f.name.endsWith(".jsonl")).map((f) => [f.name, f.text]));
  const items = [];
  for (const f of req.files) {
    if (f.name.endsWith(".jsonl")) continue;
    const got = E.recordsIn(JSON.parse(f.text), jsonl);
    for (const it of got.items) items.push(Object.assign(it, { source: req.sources[f.name] }));
  }
  const idx = E.indexRecords(items);
  const tables = req.specs.map((s) => { try { return E.buildTable(s, idx); } catch (e) { return { error: e.message }; } });
  const pvals = req.pvals.map(([t, df]) => E.twoSidedP(t, df));
  const crit = req.crit.map(([lv, df]) => E.criticalValue(lv, df));
  const hashes = await Promise.all(items.map((it) => E.recordSha256(it.record)));
  process.stdout.write(JSON.stringify({ tables, pvals, crit, hashes: items.map((it, i) => [it.record.meta.id, hashes[i]]) }));
});

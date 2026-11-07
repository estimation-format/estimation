// Builds server/_site, the static half of estrec.org: the schemas at their $ids
// (https://estrec.org/schema/...), the viewer at /viewer/, and the pages in site/.
// Run from anywhere: node server/build-site.mjs
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const out = join(here, "_site");

// Never publish dot-entries (.claude/, .DS_Store, editor files) that sit beside the sources
const copy = (from, to) => cpSync(from, to, { recursive: true, filter: (src) => !basename(src).startsWith(".") });

rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, "viewer"), { recursive: true });
copy(join(here, "site"), out);
copy(join(root, "schema"), join(out, "schema"));
for (const f of ["index.html", "estrec-table.js", "examples.js", "identifying.js", "publish.js"]) {
  copy(join(root, "viewer", f), join(out, "viewer", f));
}
console.log(`built ${out}`);

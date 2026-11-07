# estrec.org

One Cloudflare Worker serves the whole site:

- the static files (built into `_site/` by `build-site.mjs`):
  - the home page and the report, delete and 404 pages (`site/`);
  - the schemas at their `$id`s, `https://estrec.org/schema/...`;
  - the record viewer at `/viewer/`;
- the Publish service:
  - `POST /api/publish` takes `{spec, records, licence, turnstile}`. It checks them, removes
    identifying fields, stores the data in R2 and returns an unlisted link and a delete token;
  - `GET /t/<id>` renders the stored data through the viewer's web-page template, under a CSP
    that allows only that template's script, by hash. `GET /t/<id>/data` returns the JSON;
  - `DELETE /api/t/<id>` takes the delete token;
  - `POST /api/report` stores reports under `reports/` in the bucket;
- redirects from `www.estrec.org`, `estimation-record.org` and `www.estimation-record.org`.

Published tables:

- **Unlisted**: random 128-bit ids, `noindex`, no listing page.
- **Expiry**: a table expires a year after its last view. A view rewrites the stored object
  at most once a day, which also restarts the bucket's age-based lifecycle rule.
- **Licence**: CC0 1.0 by default, or CC BY 4.0 or CC BY-SA 4.0.
- **Stored**: data only, never HTML. The delete token is kept only as its SHA-256.

## Tests

```bash
node --test server/test/*.test.mjs   # no dependencies; an in-memory bucket stands in for R2
node server/build-site.mjs           # builds server/_site
```

## Setting it up (once)

Everything below runs from `server/`, in the Cloudflare account that holds the `estrec.org`
and `estimation-record.org` zones.

1. **Install wrangler and log in**

   ```bash
   cd server
   npm install
   npx wrangler login
   ```

2. **Turnstile.** In the dashboard, go to Turnstile and add a widget:

   - name `estrec`;
   - hostname `estrec.org`;
   - mode Managed.

   Then:

   - copy the **site key** into `wrangler.toml` as `TURNSTILE_SITEKEY` (it is public);
   - store the **secret key** with `npx wrangler secret put TURNSTILE_SECRET`.

   With no secret set, the Worker skips the check. That is only for `wrangler dev`.

3. **R2 lifecycle rule** (the bucket `estrecfiles` already exists). In the dashboard, go to
   R2 → estrecfiles → Settings → Object lifecycle rules → Add rule:

   - prefix `t/`;
   - delete objects 366 days after upload.

   The Worker also refuses and deletes tables not viewed for a year. The rule removes the
   ones nobody opens again.

4. **Deploy**

   ```bash
   npx wrangler deploy
   ```

   This builds `_site/` first, then attaches the four custom domains in `wrangler.toml`.
   Wrangler adds their DNS records.

5. **Check**

   - https://estrec.org/ and https://estrec.org/schema/estrec-0.1.json load;
   - https://estimation-record.org/viewer/ redirects to https://estrec.org/viewer/;
   - in the viewer, build a table, choose **Web page**, then **Publish…**;
   - open the link, then delete it with the delete link.

6. **GitHub Pages** is no longer used: `.github/workflows/pages.yml` is gone. After the repo
   moves to `estrec/estrec`, turn Pages off under Settings → Pages.

## Day to day

- **Deploy after changes** to `schema/`, `viewer/` or `server/`: run `npx wrangler deploy`
  from `server/`.
- **Develop locally**: run `npx wrangler dev`. It simulates R2 locally. Leave
  `TURNSTILE_SITEKEY` empty to skip the widget.
- **Reports**: in the dashboard, go to R2 → estrecfiles and open the `reports/<id>/` objects.
  To take a table down, delete `t/<id>.json` there.
- **Limits** (in `src/worker.js`):
  - 2 MB per upload, up to 50 records and 50 columns;
  - per IP, 10 publishes and 5 reports a minute (the `[[ratelimits]]` bindings).

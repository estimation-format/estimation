// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ted Matherly and the estrec contributors
//
// Publish: on estrec.org, send the current table spec and its records (identifying fields
// left out here, and again by the server) to /api/publish for an unlisted link. Elsewhere
// (a local copy, file://) /api/config isn't there and the Publish button stays hidden.
(function () {
  "use strict";
  var config = null, widget = null, token = null;
  var $ = function (id) { return document.getElementById(id); };

  function show(panel, nodes) {
    panel.replaceChildren.apply(panel, nodes);
    panel.hidden = false;
  }
  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) { if (k === "text") n.textContent = attrs[k]; else n.setAttribute(k, attrs[k]); });
    (kids || []).forEach(function (k) { n.append(k); });
    return n;
  }

  function loadTurnstile(box) {
    if (!config.turnstile_sitekey) return Promise.resolve(); // a development server
    return new Promise(function (resolve, reject) {
      function render() {
        widget = window.turnstile.render(box, {
          sitekey: config.turnstile_sitekey,
          callback: function (t) { token = t; resolve(); },
          "expired-callback": function () { token = null; },
          "error-callback": function () { reject(new Error("the Turnstile check couldn't load")); },
        });
      }
      if (window.turnstile) return render();
      var s = document.createElement("script");
      s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
      s.async = true;
      s.onload = render;
      s.onerror = function () { reject(new Error("the Turnstile check couldn't load")); };
      document.head.appendChild(s);
    });
  }

  function form(panel) {
    var data = window.estrecPublishData && window.estrecPublishData();
    if (!data) { show(panel, [el("span", { text: "Build a table first: add records as columns." })]); return; }
    var sel = el("select", { id: "pub-licence", "aria-label": "Licence" });
    Object.keys(config.licences).forEach(function (k) {
      var o = el("option", { value: k, text: config.licences[k].name });
      if (k === config.default_licence) o.selected = true;
      sel.append(o);
    });
    var box = el("div", { id: "pub-turnstile" });
    var go = el("button", { type: "button", class: "btn small", text: "Publish" });
    var msg = el("span", { role: "status" });
    var n = data.records.length;
    show(panel, [
      el("span", { text: "Publish this table and the " + (n === 1 ? "record" : n + " records") + " behind it at an unlisted estrec.org link. Identifying details (user, host, paths) are left out. Kept a year after its last view; you get a link to delete it. Licence: " }),
      sel, el("span", { text: " " }), go, box, msg,
    ]);
    token = null;
    var ready = loadTurnstile(box).catch(function (e) { msg.textContent = " " + e.message; });
    go.addEventListener("click", function () {
      go.disabled = true;
      msg.textContent = " Publishing…";
      ready.then(function () {
        if (config.turnstile_sitekey && !token) throw new Error("finish the check above first");
        return fetch("/api/publish", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ spec: data.spec, records: data.records, licence: sel.value, turnstile: token }),
        });
      }).then(function (r) {
        return r.json().then(function (b) { if (!r.ok) throw new Error(b.error || "publishing failed"); return b; });
      }).then(function (b) { done(panel, b); }).catch(function (e) {
        msg.textContent = " " + e.message;
        go.disabled = false;
        if (widget !== null && window.turnstile) { window.turnstile.reset(widget); token = null; }
      });
    });
  }

  function done(panel, b) {
    var link = el("a", { href: b.url, target: "_blank", rel: "noopener", text: b.url });
    var del = el("input", { type: "text", readonly: "", value: b.delete_url, "aria-label": "Delete link", class: "mono", size: "60" });
    show(panel, [
      el("span", { text: "Published: " }), link,
      el("br"), el("span", { text: "Keep this delete link; it is shown only once: " }), del,
    ]);
    del.addEventListener("focus", function () { del.select(); });
  }

  function init() {
    var btn = $("publish"), panel = $("publish-panel");
    if (!btn || !panel || location.protocol === "file:") return;
    fetch("/api/config").then(function (r) { return r.ok ? r.json() : null; }).then(function (c) {
      if (!c || !c.licences) return;
      config = c;
      btn.hidden = false;
      btn.addEventListener("click", function () {
        if (!panel.hidden) { panel.hidden = true; return; }
        form(panel);
      });
    }).catch(function () {});
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();

// Roe public site search — self-contained, buildless, works dynamic + static.
//
// The admin is a Rails app served with an importmap + Stimulus. The public
// site, though, exports to a dumb static host that can't serve importmap
// modules — so public features ship as plain <script> files, exactly like the
// theme's gallery.js / checkout.js. This is the vanilla-JS counterpart to the
// old site-search Stimulus controller.
//
// It lazily fetches the prebuilt /search-index.json on first open, then filters
// in-browser as you type. Scope is a set of facets — content sources (posts /
// pages / documentation / products), post types, and tag include/exclude. Each
// result's type is a clickable "+" pill that adds that facet; active facets
// show as removable pills above the input. Markup + classes come from the
// shared _site_search partial.
(function () {
  "use strict";

  function normalizeScope(s) {
    s = s || {};
    return {
      sources: (s.sources || []).slice(),
      postTypes: (s.postTypes || []).slice(),
      tagsInclude: (s.tagsInclude || []).slice(),
      tagsExclude: (s.tagsExclude || []).slice(),
    };
  }

  function createWidget(root) {
    var indexUrl =
      root.getAttribute("data-site-search-index-url-value") || "/search-index.json";
    var resultsWhenOpened =
      root.getAttribute("data-site-search-results-when-opened-value") === "true";
    var pageScope;
    try {
      pageScope = JSON.parse(root.getAttribute("data-site-search-scope-value") || "{}");
    } catch (e) {
      pageScope = {};
    }

    var panel = root.querySelector('[data-site-search-target="panel"]');
    var input = root.querySelector('[data-site-search-target="input"]');
    var results = root.querySelector('[data-site-search-target="results"]');
    var empty = root.querySelector('[data-site-search-target="empty"]');
    var context = root.querySelector('[data-site-search-target="context"]');
    var toggle = root.querySelector(".site-search-toggle");
    var closeBtn = root.querySelector(".site-search-close");
    if (!panel || !input || !results) return null;

    var pageFacets = normalizeScope(pageScope);
    var facets = pageFacets;
    var entries = null;
    var loading = null;
    var activeIndex = -1;

    function onDocKeydown(e) {
      if (e.key === "Escape") close();
    }
    // Close on an outside click — but never on the header toggle or a content
    // search-trigger (those manage their own open/scope behaviour).
    function onOutsideClick(e) {
      if (panel.contains(e.target)) return;
      if (root.contains(e.target)) return;
      if (e.target.closest && e.target.closest(".site-search-trigger")) return;
      close();
    }

    function open(event) {
      if (event) event.preventDefault();
      facets = normalizeScope(pageFacets);
      showPanel();
    }
    function openWithScope(scope) {
      facets = normalizeScope(scope || {});
      showPanel();
    }
    function showPanel() {
      panel.hidden = false;
      root.classList.add("site-search--open");
      activate(false);
      requestAnimationFrame(function () {
        input.focus();
      });
    }
    // Wire an open panel: document listeners, context pills, and the index.
    function activate(restore) {
      document.addEventListener("keydown", onDocKeydown);
      // Defer so the click that opened the panel doesn't immediately close it.
      // Capture phase: run before a clicked pill's handler rebuilds the DOM.
      setTimeout(function () {
        document.addEventListener("click", onOutsideClick, true);
      }, 0);
      renderContext();
      load().then(filter);
      if (restore) {
        requestAnimationFrame(function () {
          input.focus();
          var end = input.value.length;
          input.setSelectionRange(end, end);
        });
      }
    }
    function close() {
      panel.hidden = true;
      root.classList.remove("site-search--open");
      document.removeEventListener("keydown", onDocKeydown);
      document.removeEventListener("click", onOutsideClick, true);
    }

    function onKeydown(event) {
      switch (event.key) {
        case "Escape":
          close();
          break;
        case "ArrowDown":
          event.preventDefault();
          moveActive(1);
          break;
        case "ArrowUp":
          event.preventDefault();
          moveActive(-1);
          break;
        case "Enter": {
          var link = activeLink();
          if (link) {
            event.preventDefault();
            link.click();
          }
          break;
        }
      }
    }

    function resultLinks() {
      return Array.prototype.slice.call(
        results.querySelectorAll(".site-search-result-link"),
      );
    }
    function moveActive(delta) {
      var links = resultLinks();
      if (!links.length) return;
      activeIndex = (activeIndex + delta + links.length) % links.length;
      links.forEach(function (link, i) {
        var active = i === activeIndex;
        link.classList.toggle("site-search-result-link--active", active);
        if (active) link.scrollIntoView({ block: "nearest" });
      });
    }
    function activeLink() {
      var links = resultLinks();
      return activeIndex >= 0 ? links[activeIndex] : null;
    }

    function load() {
      if (entries) return Promise.resolve(entries);
      if (loading) return loading;
      loading = fetch(indexUrl, { headers: { Accept: "application/json" } })
        .then(function (r) {
          return r.ok ? r.json() : { entries: [] };
        })
        .then(function (data) {
          entries = data.entries || [];
          return entries;
        })
        .catch(function () {
          entries = [];
          return entries;
        });
      return loading;
    }

    function filter() {
      if (!entries) return;
      var tokens = input.value.trim().toLowerCase().split(/\s+/).filter(Boolean);

      // Before anything is typed, show nothing (and no "no results" message)
      // unless the site opts into results-on-open.
      if (tokens.length === 0 && !resultsWhenOpened) {
        results.innerHTML = "";
        activeIndex = -1;
        if (empty) empty.hidden = true;
        return;
      }

      var scoped = entries.filter(inScope);
      var matched;
      if (tokens.length === 0) {
        matched = scoped;
      } else {
        matched = scoped
          .map(function (e) {
            return { e: e, score: score(e, tokens) };
          })
          .filter(function (r) {
            return r.score > 0;
          })
          .sort(function (a, b) {
            return b.score - a.score;
          })
          .map(function (r) {
            return r.e;
          });
      }
      render(matched);
    }

    function addFacet(kind, value) {
      if (!value || facets[kind].indexOf(value) !== -1) return;
      facets[kind].push(value);
      renderContext();
      filter();
    }
    function removeFacet(kind, value) {
      facets[kind] = facets[kind].filter(function (v) {
        return v !== value;
      });
      renderContext();
      filter();
    }

    function inScope(entry) {
      var tags = entry.tags || [];
      if (facets.sources.length && facets.sources.indexOf(entry.type) === -1) return false;
      if (facets.postTypes.length && facets.postTypes.indexOf(entry.post_type) === -1) return false;
      if (
        facets.tagsInclude.length &&
        !facets.tagsInclude.some(function (t) {
          return tags.indexOf(t) !== -1;
        })
      )
        return false;
      if (
        facets.tagsExclude.length &&
        facets.tagsExclude.some(function (t) {
          return tags.indexOf(t) !== -1;
        })
      )
        return false;
      return true;
    }
    function score(entry, tokens) {
      var title = (entry.title || "").toLowerCase();
      var text = (entry.text || "").toLowerCase();
      var total = 0;
      for (var i = 0; i < tokens.length; i++) {
        var t = tokens[i];
        if (title.indexOf(t) !== -1) total += 3;
        else if (text.indexOf(t) !== -1) total += 1;
        else return 0;
      }
      return total;
    }
    // The facet a result exposes: post type for posts, source otherwise.
    function facetFor(entry) {
      if (entry.type === "posts" && entry.post_type) {
        return { kind: "postTypes", value: entry.post_type };
      }
      return { kind: "sources", value: entry.type };
    }

    function renderContext() {
      if (!context) return;
      var list = []
        .concat(facets.sources.map(function (v) { return { kind: "sources", value: v, label: v }; }))
        .concat(facets.postTypes.map(function (v) { return { kind: "postTypes", value: v, label: v }; }))
        .concat(facets.tagsInclude.map(function (v) { return { kind: "tagsInclude", value: v, label: "#" + v }; }))
        .concat(facets.tagsExclude.map(function (v) { return { kind: "tagsExclude", value: v, label: "−#" + v }; }));
      context.innerHTML = "";
      context.hidden = list.length === 0;
      list.forEach(function (f) {
        var pill = document.createElement("span");
        pill.className = "site-search-context-label";
        var label = document.createElement("span");
        label.className = "site-search-context-label";
        label.textContent = f.label;
        var remove = document.createElement("button");
        remove.type = "button";
        remove.className = "site-search-context-remove";
        remove.textContent = "×";
        remove.setAttribute("aria-label", "Remove " + f.label);
        remove.addEventListener("click", function () {
          removeFacet(f.kind, f.value);
        });
        pill.appendChild(label);
        pill.appendChild(remove);
        context.appendChild(pill);
      });
    }

    function render(list) {
      results.innerHTML = "";
      activeIndex = -1;
      if (empty) empty.hidden = list.length > 0;

      var frag = document.createDocumentFragment();
      list.slice(0, 50).forEach(function (e) {
        var li = document.createElement("li");
        li.className = "site-search-result";

        var a = document.createElement("a");
        a.className = "site-search-result-link";
        a.href = e.url;
        a.textContent = e.title;

        var facet = facetFor(e);
        var type = document.createElement("button");
        type.type = "button";
        type.className = "site-search-result-type";
        type.textContent = facet.value;
        var add = document.createElement("span");
        add.className = "site-search-result-type-add";
        add.textContent = "+";
        type.appendChild(add);
        type.addEventListener("click", function (ev) {
          ev.preventDefault();
          addFacet(facet.kind, facet.value);
        });

        var head = document.createElement("div");
        head.className = "site-search-result-head";
        head.appendChild(a);
        head.appendChild(type);
        if (e.paid) {
          var paid = document.createElement("span");
          paid.className = "site-search-result-paid";
          paid.textContent = "paid";
          head.appendChild(paid);
        }
        li.appendChild(head);

        if (e.excerpt) {
          var p = document.createElement("p");
          p.className = "site-search-result-excerpt";
          p.textContent = e.excerpt;
          li.appendChild(p);
        }
        frag.appendChild(li);
      });
      results.appendChild(frag);
    }

    // Local listeners — bound to fresh elements on every (Turbo) render.
    if (toggle) toggle.addEventListener("click", open);
    if (closeBtn) closeBtn.addEventListener("click", function () { close(); });
    input.addEventListener("input", filter);
    input.addEventListener("keydown", onKeydown);

    // Turbo may restore a cached page with the panel already open — re-hydrate.
    if (!panel.hidden) {
      root.classList.add("site-search--open");
      activate(true);
    }

    return {
      openWithScope: openWithScope,
      destroy: function () {
        document.removeEventListener("keydown", onDocKeydown);
        document.removeEventListener("click", onOutsideClick, true);
      },
    };
  }

  function init() {
    var root =
      document.querySelector('.site-search[data-controller~="site-search"]') ||
      document.querySelector(".site-search");
    var prev = window.__roeSiteSearch;
    if (prev && prev.root !== root && prev.widget && prev.widget.destroy) prev.widget.destroy();
    if (!root) {
      window.__roeSiteSearch = null;
      return;
    }
    if (root.__roeSearchWidget) {
      window.__roeSiteSearch = { root: root, widget: root.__roeSearchWidget };
      return;
    }
    var widget = createWidget(root);
    if (!widget) return;
    root.__roeSearchWidget = widget;
    window.__roeSiteSearch = { root: root, widget: widget };
  }

  // Global listeners once — the window flag survives Turbo body re-execution.
  if (!window.__roeSiteSearchGlobal) {
    window.__roeSiteSearchGlobal = true;
    // A content ```search block / collection `search: true` opens the overlay
    // pre-scoped by dispatching this event.
    window.addEventListener("site-search:open", function (e) {
      var cur = window.__roeSiteSearch;
      if (cur && cur.widget) cur.widget.openWithScope(e.detail && e.detail.scope);
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();

import { Controller } from "@hotwired/stimulus";

// Public site search. Lazily fetches the prebuilt /search-index.json (works
// dynamic or static), then filters it in-browser as you type.
//
// Scope is a set of facets — content sources (posts/pages/documentation/
// products) and post types (article/podcast/audio/…) plus tag include/exclude.
// Each result's type label is a `+` pill: click it to add that facet to the
// scope. Active facets show as removable pills above the input.
//
// NOTE: internal state is `this.facets`, NOT `this.scope` — Stimulus's
// Controller already defines a read-only `scope` getter (the element scope),
// so assigning `this.scope` throws and breaks connect().
//
// Values:
//   indexUrl — where to fetch the index (default /search-index.json)
//   scope    — { sources:[], postTypes:[], tagsInclude:[], tagsExclude:[] }
export default class extends Controller {
  static targets = ["panel", "input", "results", "empty", "context"];
  static values = {
    indexUrl: { type: String, default: "/search-index.json" },
    scope: { type: Object, default: {} },
    // When false, show nothing until the visitor types.
    resultsWhenOpened: { type: Boolean, default: false },
  };

  connect() {
    this.pageFacets = this.normalizeScope(this.scopeValue || {});
    this.facets = this.pageFacets;
    this.entries = null;
    this.loading = null;
    this.onDocKeydown = (e) => {
      if (e.key === "Escape") this.close();
    };
    // Close on a click outside the panel — but never on the header toggle or a
    // content search-trigger (those manage their own open/scope behaviour).
    this.onOutsideClick = (e) => {
      if (this.panelTarget.contains(e.target)) return;
      if (this.element.contains(e.target)) return;
      if (e.target.closest && e.target.closest(".site-search-trigger")) return;
      this.close();
    };
    // A content ```search block / collection `search: true` opens the overlay
    // pre-scoped by dispatching this event.
    this.onExternalOpen = (e) => this.openWithScope(e.detail && e.detail.scope);
    window.addEventListener("site-search:open", this.onExternalOpen);
  }

  disconnect() {
    window.removeEventListener("site-search:open", this.onExternalOpen);
    document.removeEventListener("keydown", this.onDocKeydown);
    document.removeEventListener("click", this.onOutsideClick, true);
  }

  normalizeScope(s) {
    return {
      sources: [...(s.sources || [])],
      postTypes: [...(s.postTypes || [])],
      tagsInclude: [...(s.tagsInclude || [])],
      tagsExclude: [...(s.tagsExclude || [])],
    };
  }

  // Header icon: open with the page's own (auto) scope.
  open(event) {
    event?.preventDefault();
    this.facets = this.normalizeScope(this.pageFacets);
    this.showPanel();
  }

  // A content search trigger requests a pre-scoped open.
  openWithScope(scope) {
    this.facets = this.normalizeScope(scope || {});
    this.showPanel();
  }

  showPanel() {
    this.panelTarget.hidden = false;
    this.element.classList.add("site-search--open");
    document.addEventListener("keydown", this.onDocKeydown);
    // Defer so the click that opened the panel doesn't immediately close it.
    // Capture phase: run before a clicked pill's handler rebuilds the DOM and
    // detaches e.target (which would make the in-panel check fail and close).
    setTimeout(
      () => document.addEventListener("click", this.onOutsideClick, true),
      0,
    );
    this.renderContext();
    this.load().then(() => this.filter());
    requestAnimationFrame(() => this.inputTarget.focus());
  }

  close() {
    this.panelTarget.hidden = true;
    this.element.classList.remove("site-search--open");
    document.removeEventListener("keydown", this.onDocKeydown);
    document.removeEventListener("click", this.onOutsideClick, true);
  }

  onKeydown(event) {
    if (event.key === "Escape") this.close();
  }

  load() {
    if (this.entries) return Promise.resolve(this.entries);
    if (this.loading) return this.loading;
    this.loading = fetch(this.indexUrlValue, {
      headers: { Accept: "application/json" },
    })
      .then((r) => (r.ok ? r.json() : { entries: [] }))
      .then((data) => {
        this.entries = data.entries || [];
        return this.entries;
      })
      .catch(() => {
        this.entries = [];
        return this.entries;
      });
    return this.loading;
  }

  filter() {
    if (!this.entries) return;
    const tokens = this.inputTarget.value
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter(Boolean);

    // Before anything is typed, show nothing (and no "no results" message)
    // unless the site opts in to results-on-open.
    if (tokens.length === 0 && !this.resultsWhenOpenedValue) {
      this.resultsTarget.innerHTML = "";
      this.emptyTarget.hidden = true;
      return;
    }

    const scoped = this.entries.filter((e) => this.inScope(e));
    const matched =
      tokens.length === 0
        ? scoped
        : scoped
            .map((e) => ({ e, score: this.score(e, tokens) }))
            .filter((r) => r.score > 0)
            .sort((a, b) => b.score - a.score)
            .map((r) => r.e);

    this.render(matched);
  }

  // Add the facet a result's type pill represents (source or post type).
  addFacet(kind, value) {
    if (!value || this.facets[kind].includes(value)) return;
    this.facets[kind].push(value);
    this.renderContext();
    this.filter();
  }

  removeFacet(kind, value) {
    this.facets[kind] = this.facets[kind].filter((v) => v !== value);
    this.renderContext();
    this.filter();
  }

  // --- internals ----------------------------------------------------------

  inScope(entry) {
    const { sources, postTypes, tagsInclude, tagsExclude } = this.facets;
    const tags = entry.tags || [];
    if (sources.length && !sources.includes(entry.type)) return false;
    if (postTypes.length && !postTypes.includes(entry.post_type)) return false;
    if (tagsInclude.length && !tagsInclude.some((t) => tags.includes(t)))
      return false;
    if (tagsExclude.length && tagsExclude.some((t) => tags.includes(t)))
      return false;
    return true;
  }

  score(entry, tokens) {
    const title = (entry.title || "").toLowerCase();
    const text = (entry.text || "").toLowerCase();
    let total = 0;
    for (const t of tokens) {
      if (title.includes(t)) total += 3;
      else if (text.includes(t)) total += 1;
      else return 0;
    }
    return total;
  }

  // The facet a result exposes: post type for posts, source otherwise.
  facetFor(entry) {
    if (entry.type === "posts" && entry.post_type) {
      return { kind: "postTypes", value: entry.post_type };
    }
    return { kind: "sources", value: entry.type };
  }

  renderContext() {
    const facets = [
      ...this.facets.sources.map((v) => ({
        kind: "sources",
        value: v,
        label: v,
      })),
      ...this.facets.postTypes.map((v) => ({
        kind: "postTypes",
        value: v,
        label: v,
      })),
      ...this.facets.tagsInclude.map((v) => ({
        kind: "tagsInclude",
        value: v,
        label: `#${v}`,
      })),
      ...this.facets.tagsExclude.map((v) => ({
        kind: "tagsExclude",
        value: v,
        label: `−#${v}`,
      })),
    ];
    this.contextTarget.innerHTML = "";
    this.contextTarget.hidden = facets.length === 0;

    for (const f of facets) {
      const pill = document.createElement("span");
      pill.className = "site-search-context-label";

      const label = document.createElement("span");
      label.className = "site-search-context-label";
      label.textContent = f.label;

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "site-search-context-remove";
      remove.textContent = "×";
      remove.setAttribute("aria-label", `Remove ${f.label}`);
      remove.addEventListener("click", () => this.removeFacet(f.kind, f.value));

      pill.append(label, remove);
      this.contextTarget.append(pill);
    }
  }

  render(entries) {
    this.resultsTarget.innerHTML = "";
    this.emptyTarget.hidden = entries.length > 0;

    const frag = document.createDocumentFragment();
    for (const e of entries.slice(0, 50)) {
      const li = document.createElement("li");
      li.className = "site-search-result";

      const a = document.createElement("a");
      a.className = "site-search-result-link";
      a.href = e.url;
      a.textContent = e.title;

      // Clickable type/post-type pill: adds the facet to the scope.
      const facet = this.facetFor(e);
      const type = document.createElement("button");
      type.type = "button";
      type.className = "site-search-result-type";
      type.textContent = facet.value;
      const add = document.createElement("span");
      add.className = "site-search-result-type-add";
      add.textContent = "+";
      type.append(add);
      type.addEventListener("click", (ev) => {
        ev.preventDefault();
        this.addFacet(facet.kind, facet.value);
      });

      const head = document.createElement("div");
      head.className = "site-search-result-head";
      head.append(a, type);
      if (e.paid) {
        const paid = document.createElement("span");
        paid.className = "site-search-result-paid";
        paid.textContent = "paid";
        head.append(paid);
      }
      li.append(head);

      if (e.excerpt) {
        const p = document.createElement("p");
        p.className = "site-search-result-excerpt";
        p.textContent = e.excerpt;
        li.append(p);
      }
      frag.append(li);
    }
    this.resultsTarget.append(frag);
  }
}

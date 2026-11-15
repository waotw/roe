import { Controller } from "@hotwired/stimulus";

// INSPECT: click something in the preview and see every rule in the theme
// that styles it, highlighted in the code, with PREV / NEXT to step through
// them like find.
//
// The rules are read from the editor's text, saved or not, and each one is
// tested with element.matches() on the clicked element, so the answer is the
// browser's own (theme_editor/matching.js has the details: :hover and
// ::before rules, @media blocks).
//
// Rules for the element in a state it isn't in right now (the play button
// while playing, a playlist while open) are listed too, in purple, labelled
// with the condition: `when [data-playing="true"]`.
//
// INSPECT stays on until INSPECTING is clicked again or Escape is pressed.
// While it's on, a click in the preview picks instead of following links. A
// shift-click goes through to the page as an ordinary click — press play,
// open a playlist — and the results follow the element's new state.
export default class extends Controller {
  static targets = ["panel", "button", "buttonLabel"];

  connect() {
    this.on = false;
    this.onLoad = (e) => this.preparePage(e.detail.doc, e.detail.win);
    this.onCss = () => this.positionOverlays();
    this.onChange = () => {
      this.cache = null;
      clearTimeout(this.changeTimer);
      this.changeTimer = setTimeout(() => this.on && this.picked && this.pick(this.picked, { keep: true }), 300);
    };
    this.element.addEventListener("theme-preview:load", this.onLoad);
    this.element.addEventListener("theme-preview:css", this.onCss);
    this.element.addEventListener("css-editor:change", this.onChange);
  }

  disconnect() {
    this.element.removeEventListener("theme-preview:load", this.onLoad);
    this.element.removeEventListener("theme-preview:css", this.onCss);
    this.element.removeEventListener("css-editor:change", this.onChange);
    clearTimeout(this.changeTimer);
  }

  get frame() {
    return this.element.querySelector(".te-preview iframe");
  }

  // ── On and off ──────────────────────────────────────────────────────────

  async toggle() {
    if (this.on) this.stop();
    else await this.start();
  }

  async start() {
    if (!this.element.cssEditor) return;
    if (!this.modules) {
      const [rules, matching] = await Promise.all([import("theme_editor/css_rules"), import("theme_editor/matching")]);
      this.modules = { rules, matching };
    }
    this.on = true;
    this.picked = null;
    this.buttonTarget.setAttribute("aria-pressed", "true");
    // COPY: the INSPECT button while it's on
    this.buttonLabelTarget.textContent = "◎ Inspecting";
    this.panelTarget.classList.remove("hidden");
    this.renderHint();
    try {
      const doc = this.frame.contentDocument;
      if (doc) this.preparePage(doc, this.frame.contentWindow);
    } catch {
      // another site's page: nothing to inspect
    }
  }

  stop() {
    this.on = false;
    this.picked = null;
    this.buttonTarget.setAttribute("aria-pressed", "false");
    this.buttonLabelTarget.textContent = "◎ Inspect";
    this.panelTarget.classList.add("hidden");
    this.panelTarget.replaceChildren();
    this.element.cssEditor?.setInspectRanges([]);
    this.teardownPage();
  }

  escape(e) {
    if (e.key === "Escape" && this.on && !e.target.closest?.("dialog, .cm-panels, .te-page-menu")) this.stop();
  }

  // ── In the preview ──────────────────────────────────────────────────────

  preparePage(doc, win) {
    this.teardownPage();
    this.picked = null;
    if (!this.on) return;
    if (this.panelTarget.querySelector(".te-inspect-rules")) this.renderHint();
    this.element.cssEditor?.setInspectRanges([]);

    this.doc = doc;
    this.win = win;
    const style = doc.createElement("style");
    style.dataset.themeEditorInspect = "";
    // Roe's own marks, drawn over the site: an id each, so the theme can't
    // reach them, and no pointer events, so they never get picked.
    style.textContent = `
      #te-hover, #te-picked { position: fixed; z-index: 2147483646; pointer-events: none; box-sizing: border-box; }
      #te-hover { outline: 1px dashed #2563eb; background: rgb(37 99 235 / 0.06); }
      #te-picked { outline: 2px solid #2563eb; }
      #te-picked span { position: absolute; left: -2px; bottom: 100%; white-space: nowrap;
        font: 11px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; color: #fff; background: #2563eb; padding: 0 6px; }
      html.te-inspecting, html.te-inspecting * { cursor: crosshair !important; }`;
    doc.head.append(style);
    doc.documentElement.classList.add("te-inspecting");
    this.hoverBox = doc.createElement("div");
    this.hoverBox.id = "te-hover";
    this.pickedBox = doc.createElement("div");
    this.pickedBox.id = "te-picked";
    this.pickedBox.hidden = true;
    doc.body.append(this.hoverBox, this.pickedBox);

    const listeners = {
      mousemove: (e) => {
        const el = this.targetOf(e);
        if (el !== this.hovered) {
          this.hovered = el;
          this.positionOverlays();
        }
      },
      mouseleave: () => {
        this.hovered = null;
        this.positionOverlays();
      },
      click: (e) => {
        if (this.passing) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        const el = this.targetOf(e);
        if (!el) return;
        if (e.shiftKey) this.passThrough(el);
        else this.pick(el);
      },
      // A press would start a drag, focus a field or submit on some
      // controls before the click arrives.
      mousedown: (e) => { if (!this.passing) { e.preventDefault(); e.stopImmediatePropagation(); } },
      submit: (e) => { e.preventDefault(); e.stopImmediatePropagation(); },
      keydown: (e) => { if (e.key === "Escape") this.stop(); },
      scroll: () => this.positionOverlays(),
    };
    for (const [type, fn] of Object.entries(listeners)) win.addEventListener(type, fn, true);
    doc.documentElement.addEventListener("mouseleave", listeners.mouseleave);
    this.listeners = listeners;
  }

  // Shift-click: the click the page would have had, without shift (a
  // shift-click on a link opens a new window). It runs inside the real
  // click, so the browser still counts it as the person's own — audio is
  // allowed to start.
  passThrough(el) {
    this.passing = true;
    try {
      el.click();
    } finally {
      this.passing = false;
    }
    this.refreshSoon();
  }

  refreshSoon() {
    clearTimeout(this.stateTimer);
    this.stateTimer = setTimeout(() => {
      if (this.on && this.picked?.isConnected) this.pick(this.picked, { keep: true });
    }, 120);
  }

  // When the picked element, or anything around it, changes state — a
  // data-playing attribute, an open <details> — the results follow. Style
  // attributes are left out: a playing player rewrites them many times a
  // second.
  watch(el) {
    this.observer?.disconnect();
    this.observer = new this.win.MutationObserver((records) => {
      if (records.some((r) => r.attributeName !== "style")) this.refreshSoon();
    });
    for (let a = el; a && a !== this.doc.documentElement; a = a.parentElement) {
      this.observer.observe(a, { attributes: true });
    }
  }

  teardownPage() {
    this.observer?.disconnect();
    this.observer = null;
    clearTimeout(this.stateTimer);
    if (!this.doc) return;
    try {
      for (const [type, fn] of Object.entries(this.listeners || {})) this.win.removeEventListener(type, fn, true);
      this.doc.documentElement.removeEventListener("mouseleave", this.listeners?.mouseleave);
      this.doc.documentElement.classList.remove("te-inspecting");
      this.doc.querySelector("style[data-theme-editor-inspect]")?.remove();
      this.hoverBox?.remove();
      this.pickedBox?.remove();
    } catch {
      // the page has gone
    }
    this.doc = this.win = this.hovered = null;
  }

  targetOf(e) {
    const el = e.target;
    if (!el || el.nodeType !== 1 || el === this.doc.documentElement || el === this.doc.body) return null;
    return el;
  }

  positionOverlays() {
    if (!this.doc) return;
    const place = (box, el) => {
      if (!el || !el.isConnected) {
        box.hidden = true;
        return;
      }
      const r = el.getBoundingClientRect();
      box.hidden = false;
      Object.assign(box.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    };
    place(this.hoverBox, this.hovered !== this.picked ? this.hovered : null);
    place(this.pickedBox, this.picked);
  }

  // ── The rules ───────────────────────────────────────────────────────────

  parsed() {
    const text = this.element.cssEditor.text();
    if (!this.cache || this.cache.text !== text) {
      const { parseRules, parseSections, variableDefinitions } = this.modules.rules;
      const rules = parseRules(text);
      this.cache = { text, rules, sections: parseSections(text), defs: variableDefinitions(rules) };
    }
    return this.cache;
  }

  pick(el, { keep = false } = {}) {
    if (!el.isConnected) {
      this.picked = null;
      this.renderHint();
      return;
    }
    const { matchRules, otherStateRules, inheritedRules } = this.modules.matching;
    const { rules } = this.parsed();
    const previous = keep && this.matches?.[this.index]?.ruleIndex;
    if (el !== this.picked) this.watch(el);
    this.picked = el;
    const matching = matchRules(el, rules, this.win);
    const others = otherStateRules(el, rules, this.win, new Set(matching.map((m) => m.ruleIndex)));
    this.matches = [...matching, ...others].sort((a, b) => a.ruleIndex - b.ruleIndex);
    this.inherited = inheritedRules(el, rules, this.win);
    const again = this.matches.findIndex((m) => m.ruleIndex === previous);
    const firstActive = this.matches.findIndex((m) => m.active && !m.state);
    this.index = again >= 0 ? again : Math.max(firstActive, 0);
    const count = matching.length;
    // COPY: the label on the picked element
    const label = this.doc.createElement("span");
    label.textContent = `${this.modules.matching.describe(el)} · ${count} ${count === 1 ? "rule" : "rules"}`;
    this.pickedBox.replaceChildren(label);
    this.positionOverlays();
    this.render({ reveal: !keep });
  }

  prev() {
    if (!this.matches?.length) return;
    this.index = (this.index - 1 + this.matches.length) % this.matches.length;
    this.render({ reveal: true });
  }

  next() {
    if (!this.matches?.length) return;
    this.index = (this.index + 1) % this.matches.length;
    this.render({ reveal: true });
  }

  goTo(i) {
    this.index = i;
    this.render({ reveal: true });
  }

  // ── The panel ───────────────────────────────────────────────────────────

  renderHint() {
    // COPY: INSPECT before anything is picked
    this.panelTarget.replaceChildren(
      h("p", { class: "te-inspect-hint" },
        h("span", { class: "te-inspect-label" }, "Inspecting"),
        " Click anything in the preview to see the rules that style it. Shift-click to use the page as normal — press play, open a playlist — without leaving INSPECT. Escape or INSPECTING to stop."),
    );
  }

  render({ reveal }) {
    const { rules } = this.parsed();
    const editor = this.element.cssEditor;
    const doc = editor.view.state.doc;
    const line = (pos) => doc.lineAt(Math.min(pos, doc.length)).number;
    const { describe } = this.modules.matching;
    const el = this.picked;

    // Where the element sits: up to four ancestors above it, each clickable.
    const chain = [];
    for (let a = el; a && a !== this.doc.body && a !== this.doc.documentElement; a = a.parentElement) chain.unshift(a);
    const shown = chain.slice(-5);
    const crumbs = h("div", { class: "te-inspect-crumbs" }, h("span", { class: "te-inspect-label" }, "Inspecting"));
    if (chain.length > shown.length) crumbs.append(h("span", { class: "te-crumb-more" }, "…"));
    shown.forEach((a, i) => {
      if (i) crumbs.append(h("span", { class: "te-crumb-sep" }, "›"));
      const b = h("button", { type: "button", class: "te-crumb" }, describe(a));
      if (a === el) b.setAttribute("aria-current", "true");
      else b.addEventListener("click", () => this.pick(a));
      crumbs.append(b);
    });

    const count = this.matches.length;
    const states = this.matches.filter((m) => m.state).length;
    const nav = h("div", { class: "te-inspect-nav" });
    // COPY: INSPECT results
    if (count) {
      const prev = h("button", { type: "button", class: "te-small-button" }, "‹ Prev");
      const next = h("button", { type: "button", class: "te-small-button" }, "Next ›");
      prev.addEventListener("click", () => this.prev());
      next.addEventListener("click", () => this.next());
      nav.append(
        h("strong", {}, `${this.index + 1} of ${count} ${count === 1 ? "rule" : "rules"}`), prev, next,
        h("span", { class: "te-inspect-note" },
          "in file order · grey: inside an @media block this preview doesn't meet" +
          (states ? ` · purple: ${states} for another state — shift-click the page to change it` : "")),
      );
    } else {
      nav.append(h("span", { class: "te-inspect-note" }, `No rule in this theme styles ${describe(el)} itself. What it inherits is below.`));
    }

    const list = h("ol", { class: "te-inspect-rules" });
    this.matches.forEach((m, i) => {
      const rule = rules[m.ruleIndex];
      const where = rule.context.map((c) => `@${c.kind} ${c.query}`).join(" · ");
      const note = [m.label, where].filter(Boolean).join(" · ");
      const row = h("li", {},
        h("button", { type: "button" },
          h("span", { class: "te-line" }, String(line(rule.from))),
          h("span", { class: "te-selector" }, m.selector.text),
          h("span", { class: "te-note" }, note)));
      if (i === this.index) row.dataset.current = "";
      if (!m.active) row.dataset.inactive = "";
      if (m.state) row.dataset.state = "";
      row.querySelector("button").addEventListener("click", () => this.goTo(i));
      list.append(row);
    });

    const parts = [crumbs, nav, list];

    // The variables the current rule uses, each a link to where it's set.
    const current = this.matches[this.index];
    if (current) {
      const chips = this.variableChips(rules[current.ruleIndex].decls, line);
      if (chips.length) parts.push(h("div", { class: "te-inspect-row" }, h("span", { class: "te-inspect-label" }, "Variables"), ...chips));
    }

    // Inherited: what the element takes from the elements around it.
    for (const inh of this.inherited) {
      const rule = rules[inh.ruleIndex];
      const row = h("div", { class: "te-inspect-row" },
        h("span", { class: "te-inspect-label" }, "Inherited from"),
        h("button", { type: "button", class: "te-crumb" }, describe(inh.element)),
        h("button", { type: "button", class: "te-line te-link" }, String(line(rule.from))));
      row.children[1].addEventListener("click", () => this.pick(inh.element));
      row.children[2].addEventListener("click", () => editor.reveal(rule.from, rule.from));
      for (const d of inh.decls) row.append(h("code", {}, `${d.prop}: ${d.value}`));
      row.append(...this.variableChips(inh.decls, line));
      parts.push(row);
    }

    this.panelTarget.replaceChildren(...parts);
    this.panelTarget.querySelector("[data-current]")?.scrollIntoView({ block: "nearest" });

    editor.setInspectRanges(this.matches.map((m, i) => ({
      from: rules[m.ruleIndex].from,
      to: rules[m.ruleIndex].to,
      kind: i === this.index ? "current" : !m.active ? "dim" : m.state ? "state" : "match",
    })));
    if (reveal && current) editor.reveal(rules[current.ruleIndex].from, rules[current.ruleIndex].from);
  }

  // "--font-mono → THEME VARIABLES, line 38", for each variable the
  // declarations use that the theme sets somewhere.
  variableChips(decls, line) {
    const { variablesIn, sectionAt } = this.modules.rules;
    const { defs, sections } = this.parsed();
    const editor = this.element.cssEditor;
    const seen = new Set();
    const chips = [];
    for (const d of decls) {
      for (const name of variablesIn(d.value)) {
        if (seen.has(name)) continue;
        seen.add(name);
        const def = defs.get(name)?.[0];
        if (!def) continue;
        const { section } = sectionAt(sections, def.from);
        const chip = h("button", { type: "button", class: "te-var" },
          `${name} → ${section ? `${section.name}, ` : ""}line ${line(def.from)}`);
        chip.addEventListener("click", () => {
          editor.reveal(def.from, def.from + name.length, { select: true });
          editor.view.focus();
        });
        chips.push(chip);
      }
    }
    return chips;
  }
}

// A small element builder for the panel: h("span", { class: "x" }, "text", child)
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  el.append(...children);
  return el;
}

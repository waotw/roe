import { Controller } from "@hotwired/stimulus";

// The preview beside the theme's code: the site in a frame, drawn with the
// CSS in the editor as you type it, saved or not. SAVE writes the file; the
// preview never waits for it.
//
// It opens on the page you last previewed, or the TEXT reference page the
// first time. Links work as on the site. The page menu jumps to any reference
// page, the home page or a typed path.
//
// The width menu sets the frame's width: the whole pane, a common device
// width, or one of the widths where this theme's layout changes, read from
// its @media queries as you edit. A width wider than the pane is scaled down
// to fit, so the page is laid out at that width but shown smaller.
//
// Below about 1100px the preview is hidden behind the PREVIEW button.
//
// After every page load it fires theme-preview:load { doc, win } on the
// element, which is how INSPECT finds the page.
export default class extends Controller {
  static targets = [
    "body", "pane", "pathButton", "menu", "frame", "frameWrap",
    "widthButton", "widthMenu", "previewToggle",
  ];
  static values = { theme: String, reference: Array };

  static PATH = "roe.themeEditor.path";
  static WIDTH = "roe.themeEditor.width";

  // COPY: common preview widths
  static COMMON = [
    { label: "Laptop", width: 1280 },
    { label: "Tablet", width: 768 },
    { label: "Phone", width: 390 },
  ];
  static NARROW_OPEN = "roe.themeEditor.preview";

  connect() {
    this.css = null;
    this.onChange = (e) => this.scheduleCss(e.detail.text);
    this.onReady = () => this.scheduleCss(this.element.cssEditor.text());
    this.element.addEventListener("css-editor:change", this.onChange);
    this.element.addEventListener("css-editor:ready", this.onReady);
    if (this.element.cssEditor) this.onReady();

    this.onOutside = (e) => {
      if (!e.target.closest(".te-page-menu:not(.te-width-menu)")) this.closeMenu();
      if (!e.target.closest(".te-width-menu")) this.closeWidthMenu();
    };
    document.addEventListener("click", this.onOutside);

    this.narrow = window.matchMedia("(max-width: 1099px)");
    this.onNarrow = () => this.layout();
    this.narrow.addEventListener("change", this.onNarrow);

    this.resizer = new ResizeObserver(() => this.fit());
    this.resizer.observe(this.frameWrapTarget);
    const saved = localStorage.getItem(this.constructor.WIDTH);
    this.setWidth(/^\d+$/.test(saved || "") ? Number(saved) : "full");
    this.layout();
    this.load(localStorage.getItem(this.constructor.PATH) || this.referenceValue[0]?.path || "/");
  }

  disconnect() {
    this.element.removeEventListener("css-editor:change", this.onChange);
    this.element.removeEventListener("css-editor:ready", this.onReady);
    document.removeEventListener("click", this.onOutside);
    this.narrow.removeEventListener("change", this.onNarrow);
    this.resizer?.disconnect();
    clearTimeout(this.cssTimer);
  }

  // ── Which page ──────────────────────────────────────────────────────────

  // A path as the site knows it, with the editor's own parameters added:
  // preview_theme so the first paint is this theme, and in_editor so a
  // reference page leaves out its own bar (this menu does that job here).
  frameUrl(path) {
    const url = new URL(path, window.location.origin);
    url.searchParams.set("preview_theme", this.themeValue);
    url.searchParams.set("in_editor", "1");
    return url.pathname + url.search + url.hash;
  }

  // The path without the editor's parameters, for the menu and for next time.
  sitePath(loc) {
    const url = new URL(loc.href);
    url.searchParams.delete("preview_theme");
    url.searchParams.delete("in_editor");
    return url.pathname + url.search + url.hash;
  }

  load(path) {
    this.closeMenu();
    this.frameTarget.src = this.frameUrl(path);
  }

  loaded() {
    let doc, win;
    try {
      doc = this.frameTarget.contentDocument;
      win = this.frameTarget.contentWindow;
      if (!doc || !win.location.href.startsWith(window.location.origin)) return;
    } catch {
      return; // another site's page: nothing to style or inspect
    }
    this.path = this.sitePath(win.location);
    localStorage.setItem(this.constructor.PATH, this.path);
    this.pathButtonTarget.textContent = `${this.path} ▾`;

    // A link followed in the preview keeps the editor's parameters.
    doc.addEventListener("click", (e) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey) return;
      const a = e.target.closest?.("a[href]");
      if (!a || (a.target && a.target !== "_self")) return;
      const url = new URL(a.href, win.location.href);
      if (url.origin !== window.location.origin || url.searchParams.has("preview_theme")) return;
      if (url.pathname === win.location.pathname && url.hash) return; // a jump within the page
      e.preventDefault();
      this.load(url.pathname + url.search + url.hash);
    });

    this.applyCss();
    this.dispatch("load", { detail: { doc, win } });
  }

  // ── The CSS ─────────────────────────────────────────────────────────────

  scheduleCss(text) {
    this.css = text;
    clearTimeout(this.cssTimer);
    this.cssTimer = setTimeout(() => this.applyCss(), 120);
  }

  // The theme's stylesheet link is switched off and the editor's text put in
  // a <style> in its place. Only the theme's link: the fonts, the site's
  // Custom Code and anything else on the page stay as they are.
  applyCss() {
    if (this.css === null) return;
    let doc;
    try {
      doc = this.frameTarget.contentDocument;
    } catch {
      return;
    }
    if (!doc?.head) return;
    let style = doc.querySelector("style[data-theme-editor]");
    if (!style) {
      const link = doc.querySelector('link[rel="stylesheet"][href*="/theme/"]');
      style = doc.createElement("style");
      style.dataset.themeEditor = "";
      if (link) {
        link.disabled = true;
        link.after(style);
      } else {
        doc.head.append(style);
      }
    }
    if (style.textContent !== this.css) {
      style.textContent = this.css;
      this.dispatch("css", { detail: { doc } });
    }
  }

  // ── The page menu ───────────────────────────────────────────────────────

  toggleMenu() {
    if (this.menuTarget.classList.contains("hidden")) this.openMenu();
    else this.closeMenu();
  }

  openMenu() {
    this.closeWidthMenu();
    // COPY: the page menu's headings
    const menu = this.menuTarget;
    menu.replaceChildren();
    const heading = (text) => {
      const h = document.createElement("div");
      h.className = "te-page-heading";
      h.textContent = text;
      menu.append(h);
    };
    const item = (label, path, current = false) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "te-page-item";
      b.textContent = label;
      if (current) b.setAttribute("aria-current", "true");
      b.addEventListener("click", () => this.load(path));
      menu.append(b);
    };
    heading("This page");
    item(this.path || "/", this.path || "/", true);
    heading("Theme reference");
    for (const page of this.referenceValue) item(page.title, page.path, page.path === this.path);
    heading("Site");
    item("Home  /", "/", this.path === "/");

    const form = document.createElement("form");
    form.className = "te-page-path";
    const input = document.createElement("input");
    input.type = "text";
    input.placeholder = "Type a path…";
    input.setAttribute("aria-label", "Path to preview");
    form.append(input);
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const value = input.value.trim();
      if (value) this.load(value.startsWith("/") ? value : `/${value}`);
    });
    menu.append(form);

    menu.classList.remove("hidden");
    this.pathButtonTarget.setAttribute("aria-expanded", "true");
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden");
    this.pathButtonTarget.setAttribute("aria-expanded", "false");
  }

  // ── Width and showing the preview ───────────────────────────────────────

  async toggleWidthMenu() {
    if (!this.widthMenuTarget.classList.contains("hidden")) return this.closeWidthMenu();
    this.closeMenu();
    const { breakpoints } = await import("theme_editor/css_rules");
    const menu = this.widthMenuTarget;
    menu.replaceChildren();
    // COPY: the width menu
    const heading = (text) => {
      const h = document.createElement("div");
      h.className = "te-page-heading";
      h.textContent = text;
      menu.append(h);
    };
    const item = (label, width, note = "") => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "te-page-item";
      b.textContent = label;
      if (note) {
        const n = document.createElement("span");
        n.className = "te-width-note";
        n.textContent = note;
        b.append(n);
      }
      if (width === this.width) b.setAttribute("aria-current", "true");
      b.addEventListener("click", () => {
        this.setWidth(width);
        this.closeWidthMenu();
      });
      menu.append(b);
    };
    item("Full width", "full", "the whole pane");
    heading("Common");
    for (const c of this.constructor.COMMON) item(`${c.label}  ${c.width}px`, c.width);
    const points = breakpoints(this.css ?? "");
    heading(points.length ? "Where this theme changes" : "This theme has no width breakpoints");
    for (const p of points) item(`${p.width}px`, p.width, `${p.queries} @media`);
    menu.classList.remove("hidden");
    this.widthButtonTarget.setAttribute("aria-expanded", "true");
  }

  closeWidthMenu() {
    this.widthMenuTarget.classList.add("hidden");
    this.widthButtonTarget.setAttribute("aria-expanded", "false");
  }

  setWidth(width) {
    this.width = width;
    localStorage.setItem(this.constructor.WIDTH, String(width));
    this.frameWrapTarget.dataset.width = width === "full" ? "full" : "fixed";
    this.fit();
  }

  // A set width wider than the pane is scaled down: the page is laid out at
  // that width (its @media rules see it), then drawn smaller.
  fit() {
    const frame = this.frameTarget;
    const label = this.widthButtonTarget;
    if (this.width === "full" || !this.width) {
      Object.assign(frame.style, { width: "", height: "", transform: "", marginLeft: "" });
      label.textContent = "Full width ▾";
      return;
    }
    const pane = this.frameWrapTarget;
    const scale = Math.min(1, pane.clientWidth / this.width);
    Object.assign(frame.style, {
      width: `${this.width}px`,
      height: `${pane.clientHeight / scale}px`,
      transform: scale < 1 ? `scale(${scale})` : "",
      marginLeft: scale < 1 ? "0" : "",
    });
    label.textContent = `${this.width}px${scale < 1 ? ` · ${Math.round(scale * 100)}%` : ""} ▾`;
  }

  togglePreview() {
    const open = this.bodyTarget.dataset.preview !== "open";
    localStorage.setItem(this.constructor.NARROW_OPEN, open ? "open" : "closed");
    this.layout();
  }

  // Wide windows always show the preview. Narrow ones show it only after
  // PREVIEW, and remember the choice.
  layout() {
    const narrow = this.narrow.matches;
    const open = !narrow || localStorage.getItem(this.constructor.NARROW_OPEN) === "open";
    this.bodyTarget.dataset.preview = open ? "open" : "closed";
    this.bodyTarget.dataset.narrow = narrow;
    this.previewToggleTarget.setAttribute("aria-pressed", open);
  }
}

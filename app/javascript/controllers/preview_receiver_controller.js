import { Controller } from "@hotwired/stimulus";

// Runs in the PREVIEW tab — a separate window from the editor — and updates it
// in place from messages the editor sends over a BroadcastChannel:
//
//   "render"  — the editor rendered the current (unsaved) content server-side
//               and sent the resulting <main> HTML. Swap it in without a reload,
//               preserving scroll, and reveal the edited block if it happens to
//               be off-screen.
//   "refresh" — full reload (used by the theme editor: a CSS change needs the
//               stylesheet re-fetched), preserving scroll across the reload.
//
// Attached to <main> only when @preview_mode is set (see layouts/site.html.erb).
export default class extends Controller {
  static values = { id: String };

  connect() {
    // Naming the window lets the editor's Preview action (a POST form targeting
    // this name) reuse this tab instead of opening a new one.
    window.name = this.idValue;

    this.channel = new BroadcastChannel(`preview-${this.idValue}`);
    this.channel.onmessage = (event) => this.handleMessage(event);

    // Theme previews apply CSS live: announce we're ready so the editor
    // pushes the current (unsaved) CSS immediately, without waiting for the
    // next keystroke. Harmless for content previews (editor ignores it).
    if (this.idValue.startsWith("theme-")) {
      this.channel.postMessage({ action: "preview-ready" });
    }

    // Restore scroll position after a refresh-triggered reload.
    const savedScroll = sessionStorage.getItem("previewScrollPosition");
    if (savedScroll !== null) {
      window.scrollTo(0, parseInt(savedScroll));
      sessionStorage.removeItem("previewScrollPosition");
    }
  }

  disconnect() {
    if (this.channel) this.channel.close();
  }

  handleMessage(event) {
    const data = event.data || {};

    if (data.action === "render" && typeof data.html === "string") {
      this.render(data.html);
      return;
    }

    if (data.action === "css" && typeof data.css === "string") {
      this.applyCss(data.css);
      return;
    }

    if (data.action === "refresh") {
      sessionStorage.setItem("previewScrollPosition", window.scrollY);
      window.location.reload();
    }
  }

  // Live theme preview: replace the file-based theme stylesheet with the
  // editor's unsaved CSS. On the first update we disable the <link> so the
  // injected <style> alone governs the cascade; later updates just rewrite
  // its text — no reload, scroll preserved. A save triggers a full "refresh"
  // reload, which drops this <style> and re-fetches the saved file.
  applyCss(css) {
    if (!this.liveThemeStyle) {
      document
        .querySelectorAll('link[rel="stylesheet"][href*="/theme/"]')
        .forEach((link) => { link.disabled = true; });
      this.liveThemeStyle = document.createElement("style");
      this.liveThemeStyle.setAttribute("data-live-theme", "");
      document.head.appendChild(this.liveThemeStyle);
    }
    this.liveThemeStyle.textContent = css;
  }

  render(html) {
    const main = this.element;

    // Locate the changed block (as an index path) before swapping the DOM.
    const staged = document.createElement("main");
    staged.innerHTML = html;
    const path = this.firstChangedPath(main, staged);

    const y = window.scrollY;
    main.innerHTML = html;
    window.scrollTo(0, y);

    // Reveal the changed block only if it's off-screen; an in-view edit never
    // causes a jump.
    let el = main;
    for (const idx of path) {
      el = el.children[idx];
      if (!el) break;
    }
    if (el && el !== main) {
      const rect = el.getBoundingClientRect();
      const visible = rect.top < window.innerHeight && rect.bottom > 0;
      if (!visible) {
        el.scrollIntoView({ behavior: "instant", block: "center" });
      }
    }
  }

  // Descend in lock-step through matching children until the tree structure
  // diverges, returning the index path to the innermost changed node. The page
  // wraps content in a single <article>, so a shallow child diff is useless.
  firstChangedPath(oldEl, newEl) {
    const path = [];
    let a = oldEl;
    let b = newEl;
    while (true) {
      const ac = a.children;
      const bc = b.children;
      if (ac.length !== bc.length) {
        // A block was added/removed: reveal the first divergent child.
        const n = Math.max(ac.length, bc.length);
        for (let i = 0; i < n; i++) {
          const av = ac[i] && ac[i].outerHTML;
          const bv = bc[i] && bc[i].outerHTML;
          if (av !== bv) {
            path.push(i);
            break;
          }
        }
        break;
      }
      let idx = -1;
      for (let i = 0; i < bc.length; i++) {
        if (ac[i].outerHTML !== bc[i].outerHTML) {
          idx = i;
          break;
        }
      }
      if (idx === -1) break; // structurally identical, text-only change
      path.push(idx);
      a = ac[idx];
      b = bc[idx];
    }
    return path;
  }
}

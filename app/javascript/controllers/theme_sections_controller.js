import { Controller } from "@hotwired/stimulus";

// The SECTIONS list beside the theme's code: every `/* ==== NAME ==== */`
// heading in the editor's text, and the `/* ---- Name ---- */` subsections
// of the one you're in. Clicking one scrolls the code to it. Read from the
// text as it is, so a section you add shows up as you type it.
//
// Three states, kept for next time in localStorage:
//   open     the list sits beside the code; HIDE ‹ hides it
//   hidden   a thin strip on the left edge
//   peek     hovering the strip slides the list out over the code, without
//            moving it; it goes when the mouse leaves. KEEP OPEN, or a click
//            on the strip, opens it for good. Clicking a section closes it.
export default class extends Controller {
  static targets = ["panel", "list", "empty", "hideButton"];

  static STORE = "roe.themeEditor.sections";

  connect() {
    this.state = localStorage.getItem(this.constructor.STORE) === "hidden" ? "hidden" : "open";
    this.render();
    this.onReady = () => this.attach();
    this.onChange = () => this.scheduleRefresh();
    this.element.addEventListener("css-editor:ready", this.onReady);
    this.element.addEventListener("css-editor:change", this.onChange);
    if (this.element.cssEditor) this.attach();
  }

  disconnect() {
    this.element.removeEventListener("css-editor:ready", this.onReady);
    this.element.removeEventListener("css-editor:change", this.onChange);
    this.scroller?.removeEventListener("scroll", this.onScroll);
    clearTimeout(this.refreshTimer);
  }

  async attach() {
    if (this.attached) return;
    this.attached = true;
    this.rules = await import("theme_editor/css_rules");
    this.editor = this.element.cssEditor;
    this.scroller = this.editor.view.scrollDOM;
    this.onScroll = () => {
      cancelAnimationFrame(this.scrollFrame);
      this.scrollFrame = requestAnimationFrame(() => this.markCurrent());
    };
    this.scroller.addEventListener("scroll", this.onScroll, { passive: true });
    this.refresh();
  }

  scheduleRefresh() {
    clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(() => this.refresh(), 250);
  }

  refresh() {
    if (!this.rules) return;
    this.sections = this.rules.parseSections(this.editor.text());
    this.emptyTarget.classList.toggle("hidden", this.sections.length > 0);
    this.currentKey = null;
    this.markCurrent(true);
  }

  // The section at the top of the code's window. Its subsections are listed
  // under it; the others' stay folded away, as in the design.
  markCurrent(force = false) {
    if (!this.sections) return;
    const view = this.editor.view;
    const top = view.lineBlockAtHeight(this.scroller.scrollTop + 8).from;
    const { section, sub } = this.rules.sectionAt(this.sections, top);
    const key = `${section?.from}:${sub?.from}`;
    if (!force && key === this.currentKey) return;
    this.currentKey = key;
    this.draw(section, sub);
  }

  draw(current, currentSub) {
    const items = [];
    let inCurrent = false;
    for (const s of this.sections) {
      if (s.level === 1) inCurrent = s === current;
      if (s.level === 2 && !inCurrent) continue;
      const li = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = s.name;
      button.className = s.level === 1 ? "te-section" : "te-subsection";
      if (s === current || s === currentSub) button.setAttribute("aria-current", "true");
      button.addEventListener("click", () => this.jump(s));
      li.append(button);
      items.push(li);
    }
    this.listTarget.replaceChildren(...items);
    this.listTarget.querySelector('[aria-current="true"].te-section')?.scrollIntoView({ block: "nearest" });
  }

  jump(section) {
    this.editor.reveal(section.from, section.from, { top: true });
    this.editor.view.dispatch({ selection: { anchor: section.from } });
    this.editor.view.focus();
    if (this.state === "peek") this.setState("hidden");
  }

  // ── Open, hidden, peek ──────────────────────────────────────────────────

  hideOrPin() {
    this.setState(this.state === "open" ? "hidden" : "open");
  }

  peek() {
    if (this.state === "hidden") this.setState("peek");
  }

  unpeek() {
    if (this.state === "peek") this.setState("hidden");
  }

  pin() {
    this.setState("open");
  }

  setState(state) {
    this.state = state;
    if (state !== "peek") localStorage.setItem(this.constructor.STORE, state);
    this.render();
  }

  render() {
    this.panelTarget.dataset.state = this.state;
    // COPY: the sections list's button
    this.hideButtonTarget.textContent = this.state === "open" ? "Hide ‹" : "Keep open";
  }
}

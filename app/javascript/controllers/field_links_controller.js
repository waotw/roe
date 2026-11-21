import { Controller } from "@hotwired/stimulus";
import { load, loaded, resolve, spotIn, rank, detail, edits } from "markdown_editor/link_targets";

// The link list in the metadata fields: the same list as the content editor
// (link_targets.js), for the fields that take Markdown (FieldText) — a
// subtitle, an excerpt, a product's description, and fields of the site's
// own that a layout shows. Opens after `[[` or `](/`, or on clicking where an
// existing link's target is written (link_targets.js#spotIn).
//
// Lives on the metadata panel and listens for every text field in it, so
// fields added after the page loaded are covered too. Its own controller;
// metadata_editor reads the field's input event as for any typing.
const MARKDOWN_FIELDS = new Set(["subtitle", "excerpt", "description"]);

export default class extends Controller {
  get knownFields() {
    if (!this._known) {
      try {
        this._known = new Set(Object.keys(JSON.parse(this.element.dataset.metadataEditorKnownFieldsValue || "{}")));
      } catch {
        this._known = new Set();
      }
    }
    return this._known;
  }

  connect() {
    this.onInput = (e) => this.update(e.target, false);
    this.onClick = (e) => this.update(e.target, true);
    this.onKey = (e) => this.key(e);
    this.onBlur = () => setTimeout(() => this.close(), 150);
    this.onScroll = () => this.place();
    this.element.addEventListener("input", this.onInput);
    this.element.addEventListener("click", this.onClick);
    this.element.addEventListener("keydown", this.onKey, true);
    this.element.addEventListener("focusout", this.onBlur);
    window.addEventListener("scroll", this.onScroll, true);
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput);
    this.element.removeEventListener("click", this.onClick);
    this.element.removeEventListener("keydown", this.onKey, true);
    this.element.removeEventListener("focusout", this.onBlur);
    window.removeEventListener("scroll", this.onScroll, true);
    this.close();
  }

  field(el) {
    if (!(el instanceof HTMLInputElement && el.type === "text") && !(el instanceof HTMLTextAreaElement)) return false;
    const name = el.dataset.metadataField || (el.id || "").replace(/^metadata-field-/, "");
    if (!name || el.name === "metadata") return false; // the raw YAML box
    // Roe's other fields (title, image, url_name…) are plain values.
    return MARKDOWN_FIELDS.has(name) || !this.knownFields.has(name);
  }

  // The spot at the caret, in field offsets.
  spotFor(el, explicit) {
    const pos = el.selectionStart;
    if (pos !== el.selectionEnd) return null;
    const start = el.value.lastIndexOf("\n", pos - 1) + 1;
    const endAt = el.value.indexOf("\n", pos);
    const line = el.value.slice(start, endAt === -1 ? undefined : endAt);
    const spot = spotIn(line, pos - start, explicit);
    return spot ? { ...spot, start, line } : null;
  }

  async update(el, explicit) {
    if (!this.field(el)) return;
    const spot = this.spotFor(el, explicit);
    if (!spot) return this.close();
    if (!loaded()) await load();

    const current = spot.current ? resolve(spot.current) : null;
    // Just clicked: the whole list, current target first. Typing narrows it.
    const list = rank(explicit ? "" : spot.query, current);
    if (!list.length) return this.close();
    this.open(el, spot, list);
  }

  open(el, spot, list) {
    this.input = el;
    this.spot = spot;
    this.list = list;
    this.selected = 0;
    if (!this.menu) {
      this.menu = document.createElement("ul");
      this.menu.className = "roe-field-link-picker";
      this.menu.setAttribute("role", "listbox");
      // mousedown, not click: the field mustn't lose focus first.
      this.menu.addEventListener("mousedown", (e) => {
        const li = e.target.closest("li");
        if (!li) return;
        e.preventDefault();
        this.pick(Number(li.dataset.index));
      });
      document.body.appendChild(this.menu);
    }
    this.menu.replaceChildren(...list.map((item, i) => this.row(item, i)));
    this.menu.hidden = false;
    this.highlight();
    this.place();
  }

  row(item, i) {
    const li = document.createElement("li");
    li.dataset.index = i;
    li.setAttribute("role", "option");
    const title = document.createElement("span");
    title.className = "roe-field-link-title";
    title.textContent = item.title;
    const path = document.createElement("span");
    path.className = "roe-field-link-path";
    path.textContent = detail(item);
    li.append(title, path);
    if (item.draft) {
      const draft = document.createElement("span");
      draft.className = "roe-field-link-draft";
      draft.textContent = "DRAFT";
      li.append(draft);
    }
    return li;
  }

  place() {
    if (!this.menu || this.menu.hidden || !this.input) return;
    const box = this.input.getBoundingClientRect();
    this.menu.style.top = `${box.bottom + 4}px`;
    this.menu.style.left = `${Math.max(8, Math.min(box.left, window.innerWidth - this.menu.offsetWidth - 8))}px`;
  }

  highlight() {
    [...this.menu.children].forEach((li, i) => li.toggleAttribute("aria-selected", i === this.selected));
    this.menu.children[this.selected]?.scrollIntoView({ block: "nearest" });
  }

  key(e) {
    if (!this.menu || this.menu.hidden || e.target !== this.input) return;
    const moves = { ArrowDown: 1, ArrowUp: -1 };
    if (e.key in moves) {
      this.selected = (this.selected + moves[e.key] + this.list.length) % this.list.length;
      this.highlight();
    } else if (e.key === "Enter" || e.key === "Tab") {
      this.pick(this.selected);
    } else if (e.key === "Escape") {
      this.close();
    } else {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
  }

  pick(index) {
    const item = this.list?.[index];
    const { input, spot } = this;
    if (!item || !input) return;
    const { changes, caret } = edits(item, spot, spot.line.slice(spot.to));
    let value = input.value;
    // Later edits first, so the earlier offsets still hold.
    for (const c of [...changes].sort((a, b) => b.from - a.from)) {
      value = value.slice(0, spot.start + c.from) + c.insert + value.slice(spot.start + c.to);
    }
    input.value = value;
    input.setSelectionRange(spot.start + caret, spot.start + caret);
    this.close();
    input.dispatchEvent(new Event("input", { bubbles: true }));
    this.close();
  }

  close() {
    if (this.menu) this.menu.hidden = true;
    this.list = null;
  }
}

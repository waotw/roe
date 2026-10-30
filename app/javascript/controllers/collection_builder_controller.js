import { Controller } from "@hotwired/stimulus";

// Collection builder. Mounted on the editor root alongside the `editor`
// controller, so the toolbar trigger, this modal, and the textarea are all in
// scope. Presents every ```collection option as a form field (source of truth:
// CollectionBuilderSchema), then serialises the non-empty ones into a fenced
// block and inserts it at the cursor.
//
// The toolbar button reads the caret (like the layout editor's nav builder):
// "Collection" when the caret isn't on a ```collection block, amber
// "Edit Collection" when it is. Opening on a block pre-fills the form from it
// and the insert replaces it in place; opening anywhere else inserts at the
// caret as before. Both paths write through execCommand so native undo works.
//
// Deliberately isolated from editor_controller: it reads/writes the shared
// textarea directly rather than reaching into the editor controller's state.
export default class extends Controller {
  static targets = ["modal", "row", "toggleButton", "insertButton"];

  connect() {
    this.textarea = this.element.querySelector('[data-editor-target="textarea"]');
    this.savedPos = null;
    // { start, finish, indent } line range while editing an existing block.
    this.editing = null;
    this.snapshotDefaults();

    if (this.textarea) {
      this._refresh = () => this.updateToggleButton();
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea.addEventListener(ev, this._refresh));
      document.addEventListener("selectionchange", this._refresh);
    }
    this.updateToggleButton();
  }

  disconnect() {
    if (!this._refresh) return;
    ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
      this.textarea?.removeEventListener(ev, this._refresh));
    document.removeEventListener("selectionchange", this._refresh);
  }

  open(event) {
    event?.preventDefault();
    // Grab the caret position now — clicking the toolbar button blurred the
    // textarea, but selectionStart still holds the last position.
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;

    const block = this.blockAtCursor();
    if (block) {
      this.editing = { start: block.start, finish: block.finish, indent: block.indent };
      this.loadBlock(block.body);
    } else {
      // Coming back to a fresh insert after an edit: clear the loaded values so
      // they aren't re-inserted somewhere new.
      if (this.editing) this.resetFields();
      this.editing = null;
      this.syncTemplateOptions();
      this.applyDependencies();
    }
    this.updateInsertLabel();
    this.modalTarget.style.display = "flex";
  }

  // "Update" when editing an existing block, "Insert" for a fresh one.
  updateInsertLabel() {
    if (this.hasInsertButtonTarget) {
      this.insertButtonTarget.textContent = this.editing ? "Update" : "Insert";
    }
  }

  // --- caret detection ------------------------------------------------------

  // The ```collection block enclosing the caret, or null. Returns the line
  // range (inclusive of both fences), the opening fence's indent, and the body
  // lines between the fences. A leading indent is allowed so a collection
  // nested in a footnote is still found; any other fence between the caret and
  // an opener means the caret isn't inside a collection block.
  blockAtCursor() {
    const ta = this.textarea;
    if (!ta) return null;
    const lines = ta.value.split("\n");
    const caretLine = ta.value.slice(0, ta.selectionStart).split("\n").length - 1;

    let open = -1, indent = "";
    for (let i = caretLine; i >= 0; i--) {
      const m = lines[i].match(/^(\s*)```collection\s*$/);
      if (m) { open = i; indent = m[1]; break; }
      if (/^\s*```/.test(lines[i])) return null;
    }
    if (open < 0) return null;

    let close = open + 1;
    while (close < lines.length && !/^\s*```\s*$/.test(lines[close])) close++;
    if (close >= lines.length || caretLine > close) return null;

    return { start: open, finish: close, indent, body: lines.slice(open + 1, close) };
  }

  // Parse a ```collection body into a { key: value } map, matching the
  // renderer's parse_collection_config: split on the first colon, both sides
  // trimmed, and a line is only config when it has both.
  parseBlock(body) {
    const cfg = {};
    body.forEach((line) => {
      if (!line.trim()) return;
      const idx = line.indexOf(":");
      if (idx < 0) return;
      const key = line.slice(0, idx).trim();
      const value = line.slice(idx + 1).trim();
      if (key && value) cfg[key] = value;
    });
    return cfg;
  }

  // Fill the form from a block's body. Reset to defaults first so keys absent
  // from the block show their default (and get omitted again on re-insert);
  // set `source` before syncing template options so the products-only `grid`
  // option exists before `template` is applied; then set the rest and re-run
  // dependency visibility so only the live fields are shown/written.
  loadBlock(body) {
    this.resetFields();
    const cfg = this.parseBlock(body);
    if (cfg.source !== undefined) this.setField("source", cfg.source);
    this.syncTemplateOptions();
    Object.entries(cfg).forEach(([k, v]) => {
      if (k !== "source") this.setField(k, v);
    });
    this.applyDependencies();
  }

  // Set every element carrying this key — `order` and `collection` each appear
  // twice (menu group / feed group) with the same data-cb-field. Only one is
  // ever visible per template, so setting both is safe: the visible one takes
  // the value and the hidden one is skipped on insert.
  setField(key, value) {
    this.modalTarget.querySelectorAll(`[data-cb-field="${key}"]`).forEach((el) => {
      el.value = value;
      el.classList.toggle("cb-empty", !el.value);
    });
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget || !this.textarea) return;
    const editing = !!this.blockAtCursor();
    const b = this.toggleButtonTarget;
    b.textContent = editing ? "Edit Collection" : "Collection";
    b.classList.toggle("bg-amber-100", editing);
    b.classList.toggle("hover:bg-amber-200", editing);
    b.classList.toggle("border-amber-700", editing);
    b.classList.toggle("text-amber-900", editing);
    b.classList.toggle("bg-gray-200", !editing);
    b.classList.toggle("hover:bg-gray-300", !editing);
    b.classList.toggle("border-gray-800", !editing);
  }

  close(event) {
    event?.preventDefault();
    this.modalTarget.style.display = "none";
  }

  // Cancel discards the current entries and closes. A plain close (X, backdrop,
  // Escape) leaves them as-is so reopening resumes where you left off; a
  // successful insert also resets, so the next block starts fresh.
  cancel(event) {
    event?.preventDefault();
    this.editing = null;
    this.resetFields();
    this.close();
  }

  // Snapshot the modal's pristine field state once, so insert/cancel restore it.
  snapshotDefaults() {
    this.defaults = Array.from(
      this.modalTarget.querySelectorAll("input, select, textarea"),
    ).map((el) => ({
      el,
      value: el.value,
      checked: el.checked,
      placeholder: el.getAttribute("placeholder"),
    }));
  }

  resetFields() {
    (this.defaults || []).forEach(({ el, value, checked, placeholder }) => {
      el.value = value;
      el.checked = checked;
      if (placeholder === null) el.removeAttribute("placeholder");
      else el.setAttribute("placeholder", placeholder);
      el.classList.toggle("cb-empty", !el.value);
    });
    this.syncTemplateOptions();
    this.applyDependencies();
  }

  // The builder's fields live inside the post <form>, so stop Enter from
  // submitting (saving) the post; Escape closes.
  onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    } else if (event.key === "Enter" && event.target.tagName === "INPUT") {
      event.preventDefault();
    }
  }

  // Reflect emptiness (for dimming) and re-run dependency visibility when a
  // controlling field (source / show_more) changes. A source change also
  // offers/removes the products-only `grid` option and pre-selects the
  // template that source usually wants.
  fieldChanged(event) {
    const el = event.target;
    el.classList.toggle("cb-empty", !el.value);
    if (el.dataset.cbField === "source") this.applySourceDefaults();
    this.applyDependencies();
  }

  // `grid` only makes sense for products, so it isn't one of the base template
  // options — add it when the source is products, remove it otherwise (and drop
  // a stale `grid` selection when leaving products).
  syncTemplateOptions() {
    const source = this.fieldEl("source")?.value || "";
    const templateEl = this.fieldEl("template");
    if (!templateEl) return;

    const grid = Array.from(templateEl.options).find((o) => o.value === "grid");
    if (source === "products" && !grid) {
      const opt = document.createElement("option");
      opt.value = "grid";
      opt.textContent = "grid";
      // First real option, right after the blank "—".
      templateEl.insertBefore(opt, templateEl.options[1] || null);
    } else if (source !== "products" && grid) {
      if (templateEl.value === "grid") templateEl.value = "";
      grid.remove();
    }
  }

  // On a source change, refresh the grid option and pre-select the template
  // that source usually wants. Source is normally chosen first, so this makes
  // the common case one click.
  applySourceDefaults() {
    this.syncTemplateOptions();
    const templateEl = this.fieldEl("template");
    if (!templateEl) return;

    const DEFAULT_TEMPLATE = { posts: "list", pages: "menu", documentation: "list", products: "grid" };
    const wanted = DEFAULT_TEMPLATE[this.fieldEl("source")?.value || ""];
    if (wanted) {
      templateEl.value = wanted;
      templateEl.classList.toggle("cb-empty", !templateEl.value);
    }
  }

  // Show a dependent row only when all of its conditions hold; otherwise hide
  // it (and its value is excluded from the output). Conditions are a JSON array
  // rendered from the schema's depends_on.
  applyDependencies() {
    this.rowTargets.forEach((row) => {
      const raw = row.dataset.cbDepends;
      if (!raw) return;
      let conditions;
      try {
        conditions = JSON.parse(raw);
      } catch {
        return;
      }
      row.hidden = !conditions.every((c) => this.conditionMet(c));
    });
  }

  // One condition: the field's value equals `value`, or is one of `in`.
  // A missing field is treated as empty string.
  conditionMet(condition) {
    const el = this.fieldEl(condition.field);
    const value = el ? el.value : "";
    if (Array.isArray(condition.in)) return condition.in.includes(value);
    return value === condition.value;
  }

  insert(event) {
    event?.preventDefault();
    const lines = [];
    this.fieldEls().forEach((el) => {
      // Skip fields hidden by an unmet dependency.
      if (el.closest(".cb-row")?.hidden) return;
      const value = el.value.trim();
      if (value === "") return; // only fields with a value get written
      // A field still showing the site default is left out, so the block keeps
      // following that setting if it changes later. Changing it back to the
      // default counts as unchanged — the setting already says that.
      if (value === (el.dataset.cbDefault ?? "")) return;
      lines.push(`${el.dataset.cbField}: ${value}`);
    });

    // Editing indents the block to match the fence it replaces (a collection
    // nested in a footnote keeps its indent); a fresh insert isn't indented.
    const indent = this.editing ? this.editing.indent : "";
    const block =
      indent + "```collection\n" +
      lines.map((l) => indent + l).join("\n") +
      (lines.length ? "\n" : "") + indent + "```";
    const editing = this.editing;
    this.editing = null;
    this.close();

    if (this.textarea) {
      this.textarea.focus({ preventScroll: true });
      const ta = this.textarea;
      let from, to;
      if (editing) {
        // Replace the fenced block's whole line range, from the start of the
        // opening fence to the end of the closing fence.
        const all = ta.value.split("\n");
        from = all.slice(0, editing.start).join("\n").length + (editing.start > 0 ? 1 : 0);
        to = all.slice(0, editing.finish + 1).join("\n").length;
      } else {
        const pos = this.savedPos ?? ta.selectionStart;
        from = pos;
        to = pos;
      }
      ta.setSelectionRange(from, to);
      // execCommand keeps the native undo stack intact (matches the editor's
      // other inserts).
      document.execCommand("insertText", false, block);
      const end = from + block.length;
      ta.setSelectionRange(end, end);
    }

    this.resetFields();
    this.updateToggleButton();
  }

  // --- helpers -------------------------------------------------------------

  // Scope to this builder's own modal, not the whole editor root — the card
  // builder renders its fields with the same [data-cb-field] attribute inside
  // the same root, and querying the root would scoop up its `style` (small)
  // field and leak it into the inserted block.
  fieldEls() {
    return Array.from(this.modalTarget.querySelectorAll("[data-cb-field]"));
  }

  fieldEl(key) {
    return this.modalTarget.querySelector(`[data-cb-field="${key}"]`);
  }
}

import { Controller } from "@hotwired/stimulus";

// ACTION builder. Mounted on the editor root alongside `editor`, so its
// dropdown, modal, and the shared textarea are all in scope. The ACTION ▼ menu
// offers Button and Form; each opens this modal in that mode. A `for:` selector
// swaps the visible field group — the same show/hide-pre-rendered-DOM mechanism
// as card-builder's type switch. On insert, the active group's non-empty fields
// are serialised into a ```button / ```form block and dropped at the cursor.
//
// Deliberately self-contained: it owns its own dropdown (like gallery-builder)
// and reads/writes the shared textarea directly, so editor_controller is never
// touched. `for: product` is omitted on insert — a bare button IS a product
// button, which is the documented idiom.
export default class extends Controller {
  static targets = ["menu", "modal", "kindSelect", "group", "error", "title", "toggleButton", "insertButton"];

  // Kinds that live on a ```form block; everything else is a ```button. Used to
  // pick the fence and the kind selector when loading a block for editing.
  static FORM_KINDS = ["signup", "signin", "checkout", "donate", "unsubscribe", "paid_content"];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedPos = null;
    this.block = "button";
    // { start, finish, indent } line range while editing an existing block.
    this.editing = null;

    // Close the dropdown on outside-click / Escape (menu only; the modal has
    // its own overlay + Escape handler).
    this._onDocClick = (e) => {
      if (!this.hasMenuTarget || this.menuTarget.classList.contains("hidden"))
        return;
      if (!e.target.closest('[data-action-builder-menu]')) this.closeMenu();
    };
    this._onDocKey = (e) => {
      if (
        e.key === "Escape" &&
        this.hasMenuTarget &&
        !this.menuTarget.classList.contains("hidden")
      ) {
        this.closeMenu();
      }
    };
    document.addEventListener("click", this._onDocClick);
    document.addEventListener("keydown", this._onDocKey);

    if (this.textarea) {
      this._refresh = () => this.updateToggleButton();
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea.addEventListener(ev, this._refresh));
      document.addEventListener("selectionchange", this._refresh);
    }
    this.snapshotDefaults();
    this.updateToggleButton();
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick);
    document.removeEventListener("keydown", this._onDocKey);
    if (this._refresh) {
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea?.removeEventListener(ev, this._refresh));
      document.removeEventListener("selectionchange", this._refresh);
    }
  }

  // --- dropdown ------------------------------------------------------------

  toggleMenu(event) {
    event.preventDefault();
    event.stopPropagation();
    this.menuTarget.classList.toggle("hidden");
  }

  closeMenu() {
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden");
  }

  // --- modal ---------------------------------------------------------------

  // First handler on the ACTION button, ahead of #toggleMenu. On a ```button /
  // ```form block it opens that block for editing and stops the dropdown from
  // also opening; anywhere else it does nothing and the dropdown opens as usual.
  caretClick(event) {
    const block = this.blockAtCursor();
    if (!block) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    this.openForEdit(block);
  }

  openForEdit(block) {
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;
    this.editing = { start: block.start, finish: block.finish, indent: block.indent };
    this.block = block.fence; // "button" | "form"

    const cfg = this.parseBlock(block.body);
    // A bare button with no `for:` is a product button (the documented idiom).
    const kind = cfg.for || cfg.type || (block.fence === "button" ? "product" : "signup");

    // Show this block's kind selector, hide+disable the other's.
    this.kindSelectTargets.forEach((sel) => {
      const match = sel.dataset.abBlock === this.block;
      sel.hidden = !match;
      sel.disabled = !match;
    });
    if (this.hasTitleTarget) {
      this.titleTarget.textContent =
        this.block === "form" ? "Edit member form" : "Edit button";
    }
    const sel = this.activeSelect();
    if (sel && Array.from(sel.options).some((o) => o.value === kind)) {
      sel.value = kind;
    }

    this.showActiveGroup();
    this.loadFields(cfg);
    this.updateInsertLabel();
    this.clearError();
    this.closeMenu();
    this.modalTarget.style.display = "flex";
  }

  // Fill the active group's fields from a parsed config, decoding any values
  // that yamlScalar quoted on the way out. Keys not in this group (for/type,
  // stray keys) are ignored.
  loadFields(cfg) {
    const group = this.activeGroup();
    if (!group) return;
    group.querySelectorAll("[data-cb-field]").forEach((el) => {
      const raw = cfg[el.dataset.cbField];
      if (raw === undefined) return;
      el.value = this.unquoteScalar(raw);
      el.classList.toggle("cb-empty", !el.value);
    });
  }

  // --- caret detection ------------------------------------------------------

  // The ```button or ```form block enclosing the caret, or null. Returns the
  // inclusive line range (both fences), the fence tag, the opening fence's
  // indent, and the body lines. A leading indent is allowed; any other fence
  // between the caret and an opener means the caret isn't in an action block.
  blockAtCursor() {
    const ta = this.textarea;
    if (!ta) return null;
    const lines = ta.value.split("\n");
    const caretLine = ta.value.slice(0, ta.selectionStart).split("\n").length - 1;

    let open = -1, indent = "", fence = null;
    for (let i = caretLine; i >= 0; i--) {
      const m = lines[i].match(/^(\s*)```(button|form)\s*$/);
      if (m) { open = i; indent = m[1]; fence = m[2]; break; }
      if (/^\s*```/.test(lines[i])) return null;
    }
    if (open < 0) return null;

    let close = open + 1;
    while (close < lines.length && !/^\s*```\s*$/.test(lines[close])) close++;
    if (close >= lines.length || caretLine > close) return null;

    return { start: open, finish: close, indent, fence, body: lines.slice(open + 1, close) };
  }

  // Parse a block body into { key: value } (raw, still quoted if it was). Both
  // parse_button_config (line-based) and the form's YAML load reduce to
  // `key: value` here — the builder only ever writes flat scalars, and a
  // hand-written multi-line YAML value is rare enough to round-trip as its
  // first line rather than mangle it.
  parseBlock(body) {
    const cfg = {};
    body.forEach((line) => {
      const m = line.match(/^\s*([\w-]+):\s*(.*)$/);
      if (m) cfg[m[1]] = m[2].trim();
    });
    return cfg;
  }

  // Reverse of yamlScalar: a value it wrapped in double quotes is unescaped
  // back to its literal text. Anything unquoted is returned as-is.
  unquoteScalar(value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value
        .slice(1, -1)
        .replace(/\\n/g, "\n")
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, "\\");
    }
    return value;
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget || !this.textarea) return;
    const block = this.blockAtCursor();
    const b = this.toggleButtonTarget;
    if (this._defaultLabel === undefined) this._defaultLabel = b.innerHTML;
    if (block) {
      b.textContent = block.fence === "form" ? "Edit Form" : "Edit Button";
    } else {
      b.innerHTML = this._defaultLabel;
    }
    const editing = !!block;
    b.classList.toggle("bg-amber-100", editing);
    b.classList.toggle("hover:bg-amber-200", editing);
    b.classList.toggle("border-amber-700", editing);
    b.classList.toggle("text-amber-900", editing);
    b.classList.toggle("bg-gray-200", !editing);
    b.classList.toggle("hover:bg-gray-300", !editing);
    b.classList.toggle("border-gray-800", !editing);
  }

  // "Update" when editing an existing block, "Insert" for a fresh one.
  updateInsertLabel() {
    if (this.hasInsertButtonTarget) {
      this.insertButtonTarget.textContent = this.editing ? "Update" : "Insert";
    }
  }

  // Opened from an ACTION menu item carrying data-action-block (button/form)
  // and, optionally, data-action-kind to pre-select a kind (e.g. the Paywall
  // shortcut opens the form modal already set to paid_content). Always a fresh
  // insert.
  open(event) {
    event?.preventDefault();
    this.editing = null;
    this.block = event?.currentTarget?.dataset?.actionBlock || "button";
    const presetKind = event?.currentTarget?.dataset?.actionKind;
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;

    // Show this block's kind selector, hide (and disable, so it can't be the
    // "active" one) the other.
    this.kindSelectTargets.forEach((sel) => {
      const match = sel.dataset.abBlock === this.block;
      sel.hidden = !match;
      sel.disabled = !match;
    });
    if (this.hasTitleTarget) {
      // "form" is the block name in the markup; the label says what it's for,
      // since every kind behind it is a member form.
      this.titleTarget.textContent =
        this.block === "form" ? "Insert member form" : "Insert button";
    }

    // Honour a preset kind when its option exists in the active select.
    const sel = this.activeSelect();
    if (sel && presetKind &&
        Array.from(sel.options).some((o) => o.value === presetKind)) {
      sel.value = presetKind;
    }

    this.showActiveGroup();
    this.updateInsertLabel();
    this.clearError();
    this.closeMenu();
    this.modalTarget.style.display = "flex";
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
    this.clearError();
  }

  kindChanged() {
    this.showActiveGroup();
    this.clearError();
  }

  fieldChanged(event) {
    const el = event.target;
    el.classList.toggle("cb-empty", !el.value);
    this.clearError();
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    } else if (event.key === "Enter" && event.target.tagName === "INPUT") {
      // Fields live inside the post <form>; don't let Enter submit it.
      event.preventDefault();
    }
  }

  // The builder must never hand back a block that doesn't parse. Most values
  // are ordinary words and read better unquoted, but YAML takes a leading [ or
  // { as a collection, a leading # as a comment, and a newline as the end of
  // the scalar — so `signin-text: [Sign in] if you're a member` comes back as a
  // sequence followed by stray text, and the author sees a YAML error for
  // something they typed literally. Quote only those cases.
  yamlScalar(value) {
    const needsQuoting = /^[\[\{>|*&!%@`'"#]/.test(value) ||
                         /^-\s/.test(value) ||
                         /:\s|\s#|\n/.test(value);
    if (!needsQuoting) return value;

    return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
  }

  insert(event) {
    event?.preventDefault();
    const group = this.activeGroup();
    if (!group) return;

    const kind = this.activeSelect()?.value;
    const fence = this.block === "form" ? "form" : "button";

    // A bare button is already a product button, so skip the `for:` line there.
    const lines = [];
    if (!(this.block === "button" && kind === "product")) {
      lines.push(`for: ${kind}`);
    }
    group.querySelectorAll("[data-cb-field]").forEach((el) => {
      const value = el.value.trim();
      if (value === "") return; // only fields with a value get written
      lines.push(`${el.dataset.cbField}: ${this.yamlScalar(value)}`);
    });

    // Editing keeps the replaced fence's indent; a fresh insert isn't indented.
    // A quoted scalar may hold escaped newlines but never a literal one, so the
    // block is always one line per key — safe to indent line-by-line.
    const indent = this.editing ? this.editing.indent : "";
    const block =
      indent + "```" + fence + "\n" +
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
        const all = ta.value.split("\n");
        from = all.slice(0, editing.start).join("\n").length + (editing.start > 0 ? 1 : 0);
        to = all.slice(0, editing.finish + 1).join("\n").length;
      } else {
        const pos = this.savedPos ?? ta.selectionStart;
        from = pos;
        to = pos;
      }
      ta.setSelectionRange(from, to);
      document.execCommand("insertText", false, block);
      const end = from + block.length;
      ta.setSelectionRange(end, end);
    }

    this.resetFields();
    this.updateToggleButton();
  }

  showError(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true;
  }

  // --- helpers -------------------------------------------------------------

  activeSelect() {
    return this.kindSelectTargets.find(
      (sel) => sel.dataset.abBlock === this.block,
    );
  }

  showActiveGroup() {
    const kind = this.activeSelect()?.value;
    this.groupTargets.forEach((g) => {
      g.hidden = g.dataset.abKind !== kind;
    });
  }

  activeGroup() {
    const kind = this.activeSelect()?.value;
    return this.groupTargets.find((g) => g.dataset.abKind === kind);
  }
}

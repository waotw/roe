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
  static targets = ["menu", "modal", "kindSelect", "group", "error", "title"];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedPos = null;
    this.block = "button";

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
    this.snapshotDefaults();
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick);
    document.removeEventListener("keydown", this._onDocKey);
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

  // Opened from an ACTION menu item carrying data-action-block (button/form)
  // and, optionally, data-action-kind to pre-select a kind (e.g. the Paywall
  // shortcut opens the form modal already set to paid_content).
  open(event) {
    event?.preventDefault();
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

    const block = "```" + fence + "\n" + lines.join("\n") + "\n```";
    this.close();

    if (this.textarea) {
      this.textarea.focus({ preventScroll: true });
      const pos = this.savedPos ?? this.textarea.selectionStart;
      this.textarea.setSelectionRange(pos, pos);
      document.execCommand("insertText", false, block);
    }

    this.resetFields();
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

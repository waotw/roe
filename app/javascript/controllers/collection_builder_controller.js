import { Controller } from "@hotwired/stimulus";

// Collection builder. Mounted on the editor root alongside the `editor`
// controller, so the toolbar trigger, this modal, and the textarea are all in
// scope. Presents every ```collection option as a form field (source of truth:
// CollectionBuilderSchema), then serialises the non-empty ones into a fenced
// block and inserts it at the cursor.
//
// Deliberately isolated from editor_controller: it reads/writes the shared
// textarea directly rather than reaching into the editor controller's state.
export default class extends Controller {
  static targets = ["modal", "row"];

  connect() {
    this.textarea = this.element.querySelector('[data-editor-target="textarea"]');
    this.savedPos = null;
  }

  open(event) {
    event?.preventDefault();
    // Grab the caret position now — clicking the toolbar button blurred the
    // textarea, but selectionStart still holds the last position.
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;
    this.applyDependencies();
    this.modalTarget.style.display = "flex";
  }

  close(event) {
    event?.preventDefault();
    this.modalTarget.style.display = "none";
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
  // controlling field (source / show_more) changes.
  fieldChanged(event) {
    const el = event.target;
    el.classList.toggle("cb-empty", !el.value);
    this.applyDependencies();
  }

  // Show a dependent row only when its controlling field equals the required
  // value; otherwise hide it (and its value is excluded from the output).
  applyDependencies() {
    this.rowTargets.forEach((row) => {
      const depField = row.dataset.cbDependsField;
      if (!depField) return;
      const controller = this.fieldEl(depField);
      const current = controller ? controller.value : "";
      row.hidden = current !== row.dataset.cbDependsValue;
    });
  }

  insert(event) {
    event?.preventDefault();
    const lines = [];
    this.fieldEls().forEach((el) => {
      // Skip fields hidden by an unmet dependency.
      if (el.closest(".cb-row")?.hidden) return;
      const value = el.value.trim();
      if (value === "") return; // only fields with a value get written
      lines.push(`${el.dataset.cbField}: ${value}`);
    });

    const block = "```collection\n" + lines.join("\n") + "\n```";
    this.close();

    if (this.textarea) {
      this.textarea.focus({ preventScroll: true });
      const pos = this.savedPos ?? this.textarea.selectionStart;
      this.textarea.setSelectionRange(pos, pos);
      // execCommand keeps the native undo stack intact (matches the editor's
      // other inserts).
      document.execCommand("insertText", false, block);
    }
  }

  // --- helpers -------------------------------------------------------------

  fieldEls() {
    return Array.from(this.element.querySelectorAll("[data-cb-field]"));
  }

  fieldEl(key) {
    return this.element.querySelector(`[data-cb-field="${key}"]`);
  }
}

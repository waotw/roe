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
    this.syncTemplateOptions();
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

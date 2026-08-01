import { Controller } from "@hotwired/stimulus";

// The NEW POST form. Two jobs, both cosmetic — the server derives the same
// title and picks the same fields, so nothing here is load-bearing.
//
//   1. Mirror the filename into the title field's PLACEHOLDER as you type, so
//      you can see the title you'll get and leave it alone, or type over it.
//   2. Show only the chosen post type's fields. Every type's group is rendered
//      up front and hidden, so switching types costs no request.
//
// Deliberately separate from metadata_editor_controller: this form is a
// different thing with a much smaller job, and that controller is load-bearing
// for the whole editor.
export default class extends Controller {
  static targets = [
    "filename",
    "title",
    "typeGroup",
    "postType",
    "pickerModal",
    "pickerContent",
    "sku",
  ];

  connect() {
    this.filenameEditedByHand = false;
    this.syncFilename();
    this.syncType();

    // The media picker is decoupled by events: it renders itself into the
    // modal and announces a choice by bubbling `media-picker:insert`. Same
    // contract the editor uses, so the picker needs no knowledge of this form.
    this.insertHandler = this.handlePicked.bind(this);
    this.closeHandler = this.closePicker.bind(this);
    this.element.addEventListener("media-picker:insert", this.insertHandler);
    this.element.addEventListener("media-picker:close", this.closeHandler);
  }

  disconnect() {
    this.element.removeEventListener("media-picker:insert", this.insertHandler);
    this.element.removeEventListener("media-picker:close", this.closeHandler);
  }

  // --- uniqueness warnings -------------------------------------------------

  // Advisory only. A clashing episode/track number is usually a mistake, but
  // sometimes it isn't (a re-numbered series, a bonus episode), so this warns
  // and never blocks. Debounced so typing "12" doesn't check "1" first.
  checkUnique(event) {
    const input = event.currentTarget;
    const field = input.dataset.uniqueField;
    if (!field) return;

    clearTimeout(this._uniqueTimers?.[field]);
    this._uniqueTimers = this._uniqueTimers || {};
    this._uniqueTimers[field] = setTimeout(
      () => this.runUniqueCheck(input, field),
      300,
    );
  }

  runUniqueCheck(input, field) {
    const warning = this.warningFor(input);
    const value = input.value.trim();
    if (!value) return this.hideWarning(warning);

    const params = new URLSearchParams({ field, value });

    // Numbers only clash within their own show AND season, so send each scope.
    (input.dataset.uniqueScopeFields || "")
      .split(",")
      .filter(Boolean)
      .forEach((name) => {
        const el = this.element.querySelector(`[name="fields[${name}]"]`);
        params.append(`scopes[${name}]`, el ? el.value.trim() : "");
      });
    fetch(`/admin/posts/check_unique?${params}`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data || !data.taken) return this.hideWarning(warning);
        const where = data.conflict ? `"${data.conflict}"` : "another post";
        this.showWarning(warning, `Already used by ${where}.`);
      })
      .catch(() => this.hideWarning(warning));
  }

  // --- product SKU ---------------------------------------------------------

  // Snipcart keys the cart on the SKU, so a product needs one. Suggests the
  // same identifier the editor's generator would, built server-side from the
  // title and category already on this form, so what you see is what you'd get
  // if you left the field blank.
  generateSku(event) {
    event.preventDefault();
    if (!this.hasSkuTarget) return;

    const params = new URLSearchParams({
      title: this.hasTitleTarget ? this.titleTarget.value.trim() : "",
      category: this.fieldValue("category"),
    });

    fetch(`/admin/products/suggest_sku?${params}`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data || !data.sku) return;
        this.skuTarget.value = data.sku;
        this.checkSku();
      })
      .catch(() => {});
  }

  // Products have their own uniqueness endpoint (check_sku), so this doesn't
  // go through checkUnique — same advisory behaviour, different URL.
  checkSku() {
    if (!this.hasSkuTarget) return;
    const warning = this.warningFor(this.skuTarget);
    const sku = this.skuTarget.value.trim();
    if (!sku) return this.hideWarning(warning);

    clearTimeout(this._skuTimer);
    this._skuTimer = setTimeout(() => {
      fetch(`/admin/products/check_sku?sku=${encodeURIComponent(sku)}`, {
        headers: { "X-Requested-With": "XMLHttpRequest" },
      })
        .then((r) => (r.ok ? r.json() : null))
        .then((data) => {
          if (!data || !data.exists) return this.hideWarning(warning);
          this.showWarning(warning, "Already used by another product.");
        })
        .catch(() => this.hideWarning(warning));
    }, 300);
  }

  fieldValue(name) {
    const el = this.element.querySelector(`[name="fields[${name}]"]`);
    return el ? el.value.trim() : "";
  }

  // The warning lives beside the input inside the same field wrapper. Walking
  // up to the wrapper's PARENT found the first warning in the whole type group
  // — i.e. the wrong field's, or none at all.
  warningFor(input) {
    return input.closest("div")?.querySelector("[data-unique-warning]");
  }

  showWarning(el, message) {
    if (!el) return;
    el.textContent = message;
    el.hidden = false;
  }

  hideWarning(el) {
    if (!el) return;
    el.hidden = true;
  }

  // --- media picker --------------------------------------------------------

  openPicker(event) {
    event.preventDefault();
    if (!this.hasPickerModalTarget) return;

    // Remember which field asked, so the choice lands in the right input.
    this.pendingFieldId = event.currentTarget.dataset.fieldId;
    const mediaType = event.currentTarget.dataset.mediaType || "images";

    this.pickerModalTarget.style.display = "flex";
    document.body.style.overflow = "hidden";
    this.pickerContentTarget.innerHTML =
      '<div class="flex items-center justify-center h-full text-gray-400 font-mono text-sm">Loading…</div>';

    fetch(`/admin/medium/picker?media_type=${encodeURIComponent(mediaType)}`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((r) => r.text())
      .then((html) => {
        this.pickerContentTarget.innerHTML = html;
      })
      .catch(() => {
        this.pickerContentTarget.innerHTML =
          '<p class="p-4 text-red-600 font-mono text-sm">Failed to load media.</p>';
      });
  }

  closePicker(event) {
    if (event && event.preventDefault) event.preventDefault();
    if (!this.hasPickerModalTarget) return;

    this.pickerModalTarget.style.display = "none";
    document.body.style.overflow = "";
    this.pendingFieldId = null;
  }

  // One field, one path — the picker allows multi-select for the editor, so
  // take the first and ignore the rest.
  handlePicked(event) {
    const item =
      event.detail && event.detail.mediaItems && event.detail.mediaItems[0];
    if (item && this.pendingFieldId) {
      const field = document.getElementById(this.pendingFieldId);
      if (field) {
        field.value = item.path;
        field.dispatchEvent(new Event("input", { bubbles: true }));
      }
    }
    this.closePicker();
  }

  // Mirrors String#parameterize on the server: lowercase, every run of
  // non-alphanumerics becomes a single hyphen, no leading or trailing ones.
  // Kept in step by a test that runs both over the same inputs.
  filenameFrom(title) {
    return title
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  // The filename tracks the title until the writer edits it themselves; after
  // that it's theirs, and typing more of the title won't overwrite it.
  syncFilename() {
    if (!this.hasFilenameTarget || !this.hasTitleTarget) return;
    if (this.filenameEditedByHand) return;

    this.filenameTarget.value = this.filenameFrom(this.titleTarget.value);
  }

  filenameEdited() {
    // An emptied field opts back in — clear it to get the title's slug back.
    this.filenameEditedByHand = this.filenameTarget.value.trim() !== "";
  }

  syncType() {
    if (!this.hasPostTypeTarget) return;
    const selected = this.postTypeTarget.value;

    this.typeGroupTargets.forEach((group) => {
      const matches = group.dataset.postType === selected;
      group.hidden = !matches;
      // Don't submit a hidden type's inputs — switching away shouldn't leave
      // a stray `audio:` on a post that is no longer an audio post.
      group.querySelectorAll("input, select").forEach((input) => {
        input.disabled = !matches;
      });
    });
  }
}

import { Controller } from "@hotwired/stimulus";

// Ties a product's `digital` checkbox to its `file_guid` field: ticking the box
// adds the GUID row, unticking removes it. Neither belongs in the file without
// the other — a GUID on a physical product does nothing, and a digital product
// without one sells a download it can't deliver.
//
// Both directions go through metadata-editor's own paths rather than poking at
// rows directly, so the field ends up in `removedFields` (and back in the Add
// Field menu) exactly as if it had been removed by hand. Hiding the row instead
// wouldn't be enough: formToYaml starts from the original metadata, so a hidden
// field stays in the saved file.
export default class extends Controller {
  // Snipcart file GUIDs are UUIDs. Anything else is a bad paste, and the cost
  // of that lands at someone's checkout.
  static UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  connect() {
    this.onInput = (event) => {
      const field = event.target?.dataset?.metadataField;
      if (field === "digital") this.sync();
      if (field === "file_guid") this.warn();
    };
    // `input` as well as change/blur, so the warning clears the moment the
    // value looks like a GUID rather than making the user click away to find
    // out. media-field debounces its equivalent because it asks the server
    // whether a file exists; this is a regex, so it can just run.
    this.element.addEventListener("input", this.onInput);
    this.element.addEventListener("change", this.onInput);
    this.element.addEventListener("blur", this.onInput, true); // blur doesn't bubble

    this.warn();
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput);
    this.element.removeEventListener("change", this.onInput);
    this.element.removeEventListener("blur", this.onInput, true);
  }

  get editor() {
    return this.application.getControllerForElementAndIdentifier(
      this.element,
      "metadata-editor",
    );
  }

  get toggle() {
    return this.element.querySelector('[data-metadata-field="digital"]');
  }

  get guidInput() {
    return this.element.querySelector('[data-metadata-field="file_guid"]');
  }

  // Bring the GUID row into line with the checkbox.
  sync() {
    const on = this.toggle?.checked;
    const guid = this.guidInput;

    if (on && !guid) {
      this.editor?._addKnownFieldByName("file_guid", "", false);
      this.element.querySelector('[data-metadata-field="file_guid"]')?.focus();
    } else if (!on && guid) {
      // Click the row's own ✕ so the editor records the removal itself.
      guid
        .closest(".metadata-field-row")
        ?.querySelector('[data-action*="removeMetadataField"]')
        ?.click();
    }
    this.warn();
  }

  warn() {
    const guid = this.guidInput;
    if (!guid) return;

    const value = guid.value.trim();
    const message =
      value === ""
        ? "⚠ A digital product needs a file GUID from Snipcart."
        : this.constructor.UUID.test(value)
          ? ""
          : "⚠ That doesn't look like a Snipcart file GUID.";

    guid.classList.toggle("border-red-400", Boolean(message));
    this.messageFor(this.footerFor(guid), message);
  }

  // The row under the field holding the Snipcart link and the warning. The
  // server renders it, but a row added by ticking the checkbox is built by
  // metadata-editor's own buildInputHtml, which knows nothing about either —
  // so create it when it's missing and both paths look the same.
  footerFor(guid) {
    // The row's column — the div holding the field and anything that belongs
    // under it. Appending here puts the footer below the input's flex row.
    //
    // This used to insert after the input itself, which only stacked when the
    // input's parent happened to be a block. A row built by buildInputHtml
    // returns a bare <input>, so its parent is the flex row and the footer
    // landed beside the field, squashing it.
    const row = guid.closest(".metadata-field-row");
    const column = row?.querySelector(":scope > div.flex-1") || guid.parentElement;
    if (!column) return null;

    let footer = column.querySelector("[data-digital-product-footer]");
    if (footer) return footer;

    footer = document.createElement("div");
    footer.dataset.digitalProductFooter = "";
    footer.className = "flex items-center gap-3 mt-0.5";

    const link = document.createElement("a");
    link.href = "https://app.snipcart.com/dashboard/digital";
    link.target = "_blank";
    link.rel = "noopener";
    link.className =
      "text-xs text-blue-600 hover:text-blue-800 underline whitespace-nowrap";
    link.textContent = "Snipcart Digital Goods →";

    footer.appendChild(link);
    column.appendChild(footer);
    return footer;
  }

  // The warning sits beside the link, not in the field row — that row is a
  // flex container, so anything appended to it lands next to the input.
  messageFor(footer, text) {
    if (!footer) return;
    let el = footer.querySelector("[data-digital-product-warning]");

    if (!text) {
      el?.remove();
      return;
    }
    if (!el) {
      el = document.createElement("p");
      el.dataset.digitalProductWarning = "";
      el.className = "text-xs text-red-600";
      footer.appendChild(el);
    }
    if (el.textContent !== text) el.textContent = text;
  }
}

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "toolbar", "selectedCount", "form"];

  connect() {
    this.updateToolbar();
  }

  updateSelection() {
    this.updateToolbar();
  }

  updateToolbar() {
    const selectedCheckboxes = this.checkboxTargets.filter((cb) => cb.checked);
    const count = selectedCheckboxes.length;

    if (count > 0) {
      this.toolbarTarget.classList.remove("hidden");
      this.selectedCountTarget.textContent = count;
    } else {
      this.toolbarTarget.classList.add("hidden");
    }
  }

  clearSelection() {
    this.checkboxTargets.forEach((cb) => {
      cb.checked = false;
    });
    this.updateToolbar();
  }

  submitDelete(event) {
    event.preventDefault();

    const selectedCheckboxes = this.checkboxTargets.filter((cb) => cb.checked);
    const count = selectedCheckboxes.length;

    if (count === 0) {
      alert("No files selected");
      return;
    }

    const message = `Delete ${count} ${count === 1 ? "file" : "files"}? This cannot be undone.`;
    if (!confirm(message)) {
      return;
    }

    // Get the form that was created by button_to
    const form = event.target.closest("form");

    // Add hidden inputs for each selected media ID
    selectedCheckboxes.forEach((cb) => {
      const mediaId = cb.dataset.mediaId;
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "media_ids[]";
      input.value = mediaId;
      form.appendChild(input);
    });

    // Now submit the form
    form.submit();
  }

  selectAllVisible() {
    // Get only visible items (respects filters and search)
    const visibleItems = this.element.querySelectorAll(
      '[data-media-filter-target="item"]:not([style*="display: none"])',
    );

    visibleItems.forEach((item) => {
      const checkbox = item.querySelector(
        '[data-media-bulk-select-target="checkbox"]',
      );
      if (checkbox) {
        checkbox.checked = true;
      }
    });

    this.updateToolbar();
  }

  selectAll() {
    // Get only visible checkboxes (respects filters)
    const visibleItems = this.element.querySelectorAll(
      '[data-media-filter-target="item"]:not([style*="display: none"])',
    );

    visibleItems.forEach((item) => {
      const checkbox = item.querySelector(
        '[data-media-bulk-select-target="checkbox"]',
      );
      if (checkbox) {
        checkbox.checked = true;
      }
    });

    this.updateToolbar();
  }

  deselectAll() {
    this.clearSelection();
  }
}

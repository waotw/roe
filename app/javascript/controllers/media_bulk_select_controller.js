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
      this.toolbarTarget.style.display = "flex";
      this.selectedCountTarget.textContent = count;
    } else {
      this.toolbarTarget.style.display = "none";
    }
  }

  toggleItem(event) {
    const item = event.currentTarget;
    const checkbox = item.querySelector(
      '[data-media-bulk-select-target="checkbox"]',
    );
    if (!checkbox) return;

    checkbox.checked = !checkbox.checked;

    // Toggle visual selected state
    const overlay = item.querySelector(".check-overlay");
    if (checkbox.checked) {
      item.classList.add("ring-2", "ring-blue-500", "bg-blue-50");
      if (overlay) overlay.style.display = "flex";
    } else {
      item.classList.remove("ring-2", "ring-blue-500", "bg-blue-50");
      if (overlay) overlay.style.display = "none";
    }

    this.updateToolbar();
  }

  clearSelection() {
    this.checkboxTargets.forEach((cb) => {
      cb.checked = false;
    });
    // Also clear visual state for picker items
    this.element
      .querySelectorAll('[data-action*="toggleItem"]')
      .forEach((item) => {
        item.classList.remove("ring-2", "ring-blue-500", "bg-blue-50");
        const overlay = item.querySelector(".check-overlay");
        if (overlay) overlay.style.display = "none";
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

    const form = event.target.closest("form");

    selectedCheckboxes.forEach((cb) => {
      const mediaId = cb.dataset.mediaId;
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "media_ids[]";
      input.value = mediaId;
      form.appendChild(input);
    });

    form.submit();
  }

  submitInsert() {
    const selectedCheckboxes = this.checkboxTargets.filter((cb) => cb.checked);
    if (selectedCheckboxes.length === 0) return;

    const mediaItems = selectedCheckboxes.map((cb) => ({
      path: cb.dataset.filePath,
      filename: cb.dataset.filename,
    }));

    // Dispatch event up to the editor controller
    this.element.dispatchEvent(
      new CustomEvent("media-picker:insert", {
        bubbles: true,
        detail: { mediaItems },
      }),
    );
  }

  selectAllVisible() {
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

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "toolbar", "selectedCount", "form", "copyUrl"];

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
      // Copy URL only makes sense for a single selection; hide it otherwise.
      if (this.hasCopyUrlTarget) {
        this.copyUrlTarget.style.display = count === 1 ? "" : "none";
      }
    } else {
      this.toolbarTarget.style.display = "none";
    }
  }

  // Copy the selected item's media path to the clipboard. Shown only when
  // exactly one item is selected (see updateToolbar); if it's ever called with
  // several selected, it copies all their paths, one per line.
  copyUrl(event) {
    const selected = this.checkboxTargets.filter((cb) => cb.checked);
    if (selected.length === 0) return;

    const url = selected.map((cb) => cb.dataset.filePath).join("\n");
    const btn = event.currentTarget;

    navigator.clipboard
      .writeText(url)
      .then(() => this.flashCopied(btn, "Copied!"))
      .catch(() => this.flashCopied(btn, "Press ⌘/Ctrl-C"));
  }

  flashCopied(btn, message) {
    if (!btn.dataset.copyLabel) btn.dataset.copyLabel = btn.textContent.trim();
    btn.textContent = message;
    clearTimeout(this._copyTimer);
    this._copyTimer = setTimeout(() => {
      btn.textContent = btn.dataset.copyLabel;
    }, 1500);
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

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "uploadInput",
    "spinner",
    "search",
    "grid",
    "item",
    "emptyMessage",
  ];
  static values = { mediaType: String };

  connect() {
    if (this.hasSearchTarget) {
      this.searchTarget.focus();
    }
  }

  closeModal() {
    // Dispatch event up to the editor controller
    this.element.dispatchEvent(
      new CustomEvent("media-picker:close", { bubbles: true }),
    );
  }

  handleSearch(event) {
    const query = (event.target.value || "").toLowerCase().trim();

    if (!this.hasItemTarget) return;

    this.itemTargets.forEach((item) => {
      const filename = item.dataset.filename || "";
      if (query === "" || filename.includes(query)) {
        item.style.display = "";
      } else {
        item.style.display = "none";
      }
    });
  }

  async handleUpload(event) {
    const files = Array.from(event.target.files);
    if (files.length === 0) return;

    this.showSpinner();

    const token = document.querySelector('meta[name="csrf-token"]').content;
    const uploadedItems = [];

    for (const file of files) {
      try {
        const formData = new FormData();
        formData.append("file", file);

        const response = await fetch("/admin/medium", {
          method: "POST",
          headers: { "X-CSRF-Token": token },
          body: formData,
        });

        const data = await response.json();

        if (data.success) {
          uploadedItems.push({
            path: data.path,
            filename: data.filename || file.name,
          });
        } else {
          console.error("Upload failed for", file.name, data.error);
        }
      } catch (e) {
        console.error("Upload error for", file.name, e);
      }
    }

    this.hideSpinner();

    if (uploadedItems.length > 0) {
      this.addItemsToGrid(uploadedItems);
    }

    // Reset file input so same files can be re-uploaded if needed
    event.target.value = "";
  }

  addItemsToGrid(items) {
    // Remove empty message if present
    if (this.hasEmptyMessageTarget) {
      this.emptyMessageTarget.remove();
    }

    // Create grid if it doesn't exist yet
    let grid = this.hasGridTarget ? this.gridTarget : null;
    if (!grid) {
      grid = document.createElement("div");
      grid.className = "grid grid-cols-4 gap-3";
      grid.dataset.mediaPickerTarget = "grid";
      this.element
        .querySelector(".flex-1.overflow-y-auto.p-4")
        .appendChild(grid);
    }

    items.forEach((item) => {
      const basename = item.path.split("/").pop();
      const filenameNoExt = basename.replace(/\.[^/.]+$/, "");
      const ext = basename.split(".").pop().toLowerCase();

      const isImage = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "svg",
        "bmp",
      ].includes(ext);
      const isAudio = ["mp3", "m4a", "wav", "ogg", "flac", "aac"].includes(ext);

      let thumbnail = "";
      if (isImage) {
        thumbnail = `<img src="${item.path}" alt="${basename}" class="w-full h-24 object-cover mb-1" loading="lazy">`;
      } else if (isAudio) {
        thumbnail = `<div class="w-full h-24 bg-gray-200 mb-1 flex items-center justify-center"><span class="text-3xl">🎵</span></div>`;
      } else {
        thumbnail = `<div class="w-full h-24 bg-gray-200 mb-1 flex items-center justify-center"><span class="text-3xl">🎬</span></div>`;
      }

      const div = document.createElement("div");
      div.className =
        "border border-gray-300 p-1.5 hover:bg-gray-50 relative cursor-pointer transition-all ring-2 ring-blue-500 bg-blue-50";
      div.dataset.mediaPickerTarget = "item";
      div.dataset.filename = basename.toLowerCase();
      div.dataset.action = "click->media-bulk-select#toggleItem";
      div.innerHTML = `
        <div class="check-overlay absolute top-1.5 left-1.5 w-5 h-5 bg-blue-600 text-white text-xs flex items-center justify-center rounded-md z-10 pointer-events-none">✓</div>
        <input type="checkbox"
               data-media-bulk-select-target="checkbox"
               data-file-path="${item.path}"
               data-filename="${filenameNoExt}"
               class="hidden"
               checked>
        ${thumbnail}
        <p class="text-xs font-mono text-gray-600 truncate">${basename}</p>
      `;

      // Prepend so newly uploaded items appear first
      grid.prepend(div);
    });

    // Directly call updateToolbar on the media-bulk-select controller
    // so it picks up the newly added checkboxes (Stimulus already observes
    // the DOM so checkboxTargets will include the new ones by now)
    const bulkSelectController =
      this.application.getControllerForElementAndIdentifier(
        this.element,
        "media-bulk-select",
      );
    if (bulkSelectController) {
      bulkSelectController.updateToolbar();
    }
  }

  showSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden");
    }
  }

  hideSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden");
    }
  }
}

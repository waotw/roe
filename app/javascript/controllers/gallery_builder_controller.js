import { Controller } from "@hotwired/stimulus";

// Gallery insert popover. Mounted on the editor root alongside `editor`. The
// Gallery toolbar button opens a small dropdown with a single "Display as
// carousel?" checkbox; Insert drops a ```gallery block at the cursor — plain
// (grid) when unchecked, plus `slideshow: true` when checked — with the image
// placeholder selected so the author can type/paste paths or use the media
// picker.
//
// Isolated from editor_controller: it reads/writes the shared textarea itself.
export default class extends Controller {
  static targets = ["wrap", "menu", "carousel"];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedPos = null;
    this.onOutside = (e) => {
      if (this.menuTarget.classList.contains("hidden")) return;
      if (this.hasWrapTarget && this.wrapTarget.contains(e.target)) return;
      this.hide();
    };
  }

  disconnect() {
    document.removeEventListener("click", this.onOutside, true);
  }

  toggle(event) {
    event?.preventDefault();
    if (this.menuTarget.classList.contains("hidden")) this.show();
    else this.hide();
  }

  show() {
    // The button click blurred the textarea, but selectionStart is retained.
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;
    this.menuTarget.classList.remove("hidden");
    setTimeout(
      () => document.addEventListener("click", this.onOutside, true),
      0,
    );
  }

  hide() {
    this.menuTarget.classList.add("hidden");
    document.removeEventListener("click", this.onOutside, true);
  }

  insert(event) {
    event?.preventDefault();
    const carousel = this.hasCarouselTarget && this.carouselTarget.checked;
    const inner = carousel
      ? "__PLACEHOLDER__\nslideshow: true"
      : "__PLACEHOLDER__";
    const block = "```gallery\n" + inner + "\n```";

    this.hide();
    if (!this.textarea) return;

    this.textarea.focus({ preventScroll: true });
    const pos = this.savedPos ?? this.textarea.selectionStart;
    this.textarea.setSelectionRange(pos, pos);
    document.execCommand("insertText", false, block);

    // Select the placeholder so the author can immediately add images.
    const idx = block.indexOf("__PLACEHOLDER__");
    if (idx !== -1) {
      const start = pos + idx;
      this.textarea.setSelectionRange(start, start + "__PLACEHOLDER__".length);
    }
  }
}

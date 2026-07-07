import { Controller } from "@hotwired/stimulus";

// Gallery insert popover. Mounted on the editor root alongside `editor`. The
// Gallery toolbar button opens a small dropdown with a "Display as carousel?"
// checkbox and an optional caption; Insert drops a ```gallery block at the
// cursor — plain (grid) when unchecked, plus `slideshow: true` when checked,
// plus `caption: ...` when a caption is given — with the image placeholder
// selected so the author can type/paste paths or use the media picker.
//
// Isolated from editor_controller: it reads/writes the shared textarea itself.
export default class extends Controller {
  static targets = ["wrap", "menu", "carousel", "caption"];

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
    const caption = this.hasCaptionTarget ? this.captionTarget.value.trim() : "";

    // Directives follow the image placeholder, one per line. `caption:` is
    // line-based, so collapse any stray whitespace to keep it on one line.
    const directives = [];
    if (carousel) directives.push("slideshow: true");
    if (caption) directives.push("caption: " + caption.replace(/\s+/g, " "));

    const inner = ["__PLACEHOLDER__", ...directives].join("\n");
    const block = "```gallery\n" + inner + "\n```";

    // Clear both inputs on insert so the next gallery starts fresh. Closing
    // the menu without inserting leaves them as-is (hide() doesn't reset);
    // a page reload clears them anyway since they're plain form fields.
    if (this.hasCarouselTarget) this.carouselTarget.checked = false;
    if (this.hasCaptionTarget) this.captionTarget.value = "";

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

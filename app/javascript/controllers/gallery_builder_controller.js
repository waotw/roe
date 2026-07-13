import { Controller } from "@hotwired/stimulus";

// Gallery insert popover. Mounted on the editor root alongside `editor`. The
// Gallery toolbar button opens a small dropdown with a "Display as carousel?"
// checkbox, an optional aspect-ratio select, and an optional caption.
//
// Two insertion modes:
//   - No selection (cursor only): inserts a gallery block with a
//     __PLACEHOLDER__ image, selected so the author can type/paste paths.
//   - Text selected (e.g. 2+ image lines highlighted): wraps the selected
//     content in a gallery fence with the chosen directives — an easy way
//     to convert a plain run of images into a fancy gallery.
//
// Isolated from editor_controller: it reads/writes the shared textarea itself.
export default class extends Controller {
  static targets = ["wrap", "menu", "carousel", "aspect", "ratioNote", "caption"];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedStart = null;
    this.savedEnd = null;
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
    // The button click blurred the textarea, but selectionStart/End are
    // retained. Capture both so we can detect a selection vs. cursor-only.
    this.savedStart = this.textarea ? this.textarea.selectionStart : null;
    this.savedEnd = this.textarea ? this.textarea.selectionEnd : null;
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

  // Carousels size images by height, so the aspect-ratio class is a no-op
  // there. Warn when both are set rather than silently dropping one.
  updateRatioNote() {
    if (!this.hasRatioNoteTarget) return;
    const carousel = this.hasCarouselTarget && this.carouselTarget.checked;
    const aspect = this.hasAspectTarget && this.aspectTarget.value;
    this.ratioNoteTarget.classList.toggle("hidden", !(carousel && aspect));
  }

  insert(event) {
    event?.preventDefault();
    const carousel = this.hasCarouselTarget && this.carouselTarget.checked;
    const aspect = this.hasAspectTarget ? this.aspectTarget.value : "";
    const caption = this.hasCaptionTarget ? this.captionTarget.value.trim() : "";

    // Directives follow the content, one per line. Each is optional;
    // an unset control emits nothing. `caption:` is line-based, so collapse any
    // stray whitespace to keep it on one line.
    const directives = [];
    if (carousel) directives.push("slideshow: true");
    if (aspect) directives.push("aspect_ratio: " + aspect);
    if (caption) directives.push("caption: " + caption.replace(/\s+/g, " "));

    // Clear the controls on insert so the next gallery starts fresh. Closing
    // the menu without inserting leaves them as-is (hide() doesn't reset);
    // a page reload clears them anyway since they're plain form fields.
    if (this.hasCarouselTarget) this.carouselTarget.checked = false;
    if (this.hasAspectTarget) this.aspectTarget.value = "";
    if (this.hasCaptionTarget) this.captionTarget.value = "";
    this.updateRatioNote();

    this.hide();
    if (!this.textarea) return;

    this.textarea.focus({ preventScroll: true });
    const start = this.savedStart ?? this.textarea.selectionStart;
    const end = this.savedEnd ?? this.textarea.selectionEnd;

    // Detect the indent of the line containing the cursor/selection start.
    // If it's 4+ spaces we're likely inside a footnote continuation —
    // indent every line of the generated gallery block by that amount so
    // kramdown keeps it inside the footnote instead of ejecting it to body.
    const lineStart = this.textarea.value.lastIndexOf("\n", start - 1) + 1;
    const indentMatch = this.textarea.value.substring(lineStart, lineStart + 20).match(/^ */);
    const indent = indentMatch ? indentMatch[0] : "";
    const prefix = indent.length >= 4 ? indent : "";

    // If the author had text selected (e.g. 2+ image lines highlighted),
    // wrap the selected content in a gallery fence with the chosen
    // directives. Otherwise insert a blank gallery with a placeholder.
    if (start !== null && end !== null && start !== end) {
      // Normalize selected lines: trim each, then re-indent with prefix
      // so all lines share consistent indentation inside the fence.
      const content = this.textarea.value.substring(start, end)
        .split("\n")
        .map(line => {
          const trimmed = line.trim();
          return trimmed ? prefix + trimmed : "";
        })
        .join("\n");

      const directivesText = directives.length > 0
        ? "\n" + directives.map(d => prefix + d).join("\n")
        : "";

      const block = prefix + "```gallery\n" + content + directivesText + "\n" + prefix + "```";

      this.textarea.setSelectionRange(start, end);
      document.execCommand("insertText", false, block);
    } else {
      const inner = [prefix + "__PLACEHOLDER__", ...directives.map(d => prefix + d)].join("\n");
      const block = prefix + "```gallery\n" + inner + "\n" + prefix + "```";

      const pos = start ?? 0;
      this.textarea.setSelectionRange(pos, pos);
      document.execCommand("insertText", false, block);

      // Select the placeholder so the author can immediately add images.
      const idx = block.indexOf("__PLACEHOLDER__");
      if (idx !== -1) {
        this.textarea.setSelectionRange(pos + idx, pos + idx + "__PLACEHOLDER__".length);
      }
    }
  }
}

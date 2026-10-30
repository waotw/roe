import { Controller } from "@hotwired/stimulus";

// Gallery insert popover. Mounted on the editor root alongside `editor`.
//
// THE ONLY PLACE THAT WRITES GALLERY SYNTAX. The media picker can send images
// here and this can send the picker off to fetch some, but neither builds a
// block — two things that both knew what a gallery looks like would eventually
// disagree about it.
//
// Images reach the list two ways, and they end up in the same place:
//   - ADD IMAGES → the media picker → media-picker:insert-gallery
//   - a selection in the editor that already contains image lines, read out
//     when the popover opens
//
// Insertion, in order of precedence:
//   - images in the list → a gallery of those images, replacing the selection
//     they came from if that's where they came from
//   - a selection with no images in it → wrapped verbatim, the original
//     behaviour, so highlighting anything at all and reaching for Gallery still
//     does what it always did
//   - nothing → a gallery with a __PLACEHOLDER__, selected and ready to type over
export default class extends Controller {
  static targets = [
    "wrap",
    "menu",
    "toggleButton",
    "insertButton",
    "carousel",
    "aspect",
    "ratioNote",
    "caption",
    "imageList",
    "addImages",
    "clear",
  ];

  // `![alt](src)` with an optional `(*caption*)`. The space is optional to match
  // process_image_captions — see the comment there.
  static IMAGE_RE = /!\[([^\]]*)\]\(([^)]+)\)[ \t]*(?:\(\*([^*]*)\*\))?/g;

  // Directive keys a gallery body understands, mirroring GALLERY_DIRECTIVES /
  // parse_gallery in HasMarkdownExtensions. A `key: value` line with one of
  // these (and no image) is config; anything else stays content.
  static DIRECTIVES = ["slideshow", "caption", "aspect_ratio"];
  static DIRECTIVE_RE = /^\s*([a-z_]+)\s*:\s*(.+?)\s*$/i;

  static FOOTNOTE_DEF_RE = /^\[\^[^\]]+\]:/;

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedStart = null;
    this.savedEnd = null;
    // Images the gallery will be built from: { path, alt, caption }.
    this.images = [];
    // Whether those images came out of a selection, which is what decides
    // between replacing that selection and inserting at the cursor.
    this.fromSelection = false;
    // { start, finish, indent } line range while editing an existing block.
    this.editing = null;

    this.onOutside = (e) => {
      if (this.menuTarget.classList.contains("hidden")) return;
      if (this.pickerOpen) return; // clicks in the media modal aren't "outside"
      if (this.hasWrapTarget && this.wrapTarget.contains(e.target)) return;
      this.hide();
    };

    this.onPicked = (event) => this.addImages(event.detail?.mediaItems || []);
    this.element.addEventListener("media-picker:insert-gallery", this.onPicked);

    // Whether or not anything was chosen. Cancelling the picker never reaches
    // onPicked, and without this the suspension below would never lift — the
    // popover would stop closing on an outside click for the rest of the page.
    this.onPickerClosed = () => {
      this.pickerOpen = false;
    };
    this.element.addEventListener("media-picker:close", this.onPickerClosed);

    // Relabel the toolbar button to "Edit Gallery" (amber) when the caret is
    // on a ```gallery block, matching the other builders.
    if (this.textarea) {
      this._refresh = () => this.updateToggleButton();
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea.addEventListener(ev, this._refresh));
      document.addEventListener("selectionchange", this._refresh);
    }
    this.updateToggleButton();
  }

  disconnect() {
    document.removeEventListener("click", this.onOutside, true);
    this.element.removeEventListener(
      "media-picker:insert-gallery",
      this.onPicked,
    );
    this.element.removeEventListener(
      "media-picker:close",
      this.onPickerClosed,
    );
    if (this._refresh) {
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea?.removeEventListener(ev, this._refresh));
      document.removeEventListener("selectionchange", this._refresh);
    }
  }

  toggle(event) {
    event?.preventDefault();
    if (this.menuTarget.classList.contains("hidden")) this.open();
    else this.hide();
  }

  // Opened by the author. Capture the selection and decide what to start from:
  //   - caret inside a ```gallery block → edit it (load its images/directives,
  //     the insert will replace it)
  //   - a selection that holds image lines → seed from those (unchanged)
  //   - otherwise → start empty
  open() {
    this.savedStart = this.textarea ? this.textarea.selectionStart : null;
    this.savedEnd = this.textarea ? this.textarea.selectionEnd : null;

    const block = this.blockAtCursor();
    if (block) {
      this.editing = { start: block.start, finish: block.finish, indent: block.indent };
      this.loadBlock(block.body);
    } else {
      // Opening away from a block after an abandoned edit (the popover has no
      // cancel — an outside click just hides it) must not carry that block's
      // loaded images into a fresh insert. Clear them; then the usual
      // seed-from-selection applies.
      if (this.editing) this.reset();
      this.editing = null;
      if (this.images.length === 0) this.seedFromSelection();
    }
    this.updateInsertLabel();
    this.show();
  }

  // "Update" when editing an existing block, "Insert" for a fresh one.
  updateInsertLabel() {
    if (this.hasInsertButtonTarget) {
      this.insertButtonTarget.textContent = this.editing ? "Update" : "Insert";
    }
  }

  // Reopened after a trip to the picker: the selection captured on the way out
  // is still the one that matters, so nothing is recaptured here.
  show() {
    this.renderImages();
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

  // --- images ---------------------------------------------------------------

  seedFromSelection() {
    if (!this.textarea) return;
    const { savedStart: start, savedEnd: end } = this;
    if (start === null || end === null || start === end) return;

    const found = [
      ...this.textarea.value.substring(start, end).matchAll(
        this.constructor.IMAGE_RE,
      ),
    ].map(([, alt, src, caption]) => ({
      path: src.trim(),
      alt: alt.trim(),
      caption: (caption || "").trim(),
    }));

    if (found.length === 0) return; // leave it to the verbatim wrap

    this.images = found;
    this.fromSelection = true;
  }

  // --- editing an existing block --------------------------------------------

  // The ```gallery block enclosing the caret, or null. Returns the inclusive
  // line range (both fences), the opening fence's indent, and the body lines.
  // A leading indent is allowed (a gallery inside a footnote); any other fence
  // between the caret and an opener means the caret isn't in a gallery block.
  blockAtCursor() {
    const ta = this.textarea;
    if (!ta) return null;
    const lines = ta.value.split("\n");
    const caretLine = ta.value.slice(0, ta.selectionStart).split("\n").length - 1;

    let open = -1, indent = "";
    for (let i = caretLine; i >= 0; i--) {
      const m = lines[i].match(/^(\s*)```gallery\s*$/);
      if (m) { open = i; indent = m[1]; break; }
      if (/^\s*```/.test(lines[i])) return null;
    }
    if (open < 0) return null;

    let close = open + 1;
    while (close < lines.length && !/^\s*```\s*$/.test(lines[close])) close++;
    if (close >= lines.length || caretLine > close) return null;

    return { start: open, finish: close, indent, body: lines.slice(open + 1, close) };
  }

  // Split a block body into images and directive fields, matching parse_gallery:
  // a `key: value` line whose key is a known directive (and which holds no
  // image) is config; everything else is scanned for images.
  loadBlock(body) {
    const images = [];
    let slideshow = false, aspect = "", caption = "";
    body.forEach((line) => {
      const m = line.match(this.constructor.DIRECTIVE_RE);
      if (m && !/!\[/.test(line)) {
        const key = m[1].toLowerCase();
        if (this.constructor.DIRECTIVES.includes(key)) {
          if (key === "slideshow") slideshow = /^(true|yes|1|on)$/i.test(m[2].trim());
          else if (key === "aspect_ratio") aspect = m[2].trim();
          else if (key === "caption") caption = m[2].trim();
          return;
        }
      }
      for (const im of line.matchAll(this.constructor.IMAGE_RE)) {
        images.push({ path: im[2].trim(), alt: im[1].trim(), caption: (im[3] || "").trim() });
      }
    });

    this.images = images;
    this.fromSelection = false;
    if (this.hasCarouselTarget) this.carouselTarget.checked = slideshow;
    if (this.hasAspectTarget) this.aspectTarget.value = aspect;
    if (this.hasCaptionTarget) this.captionTarget.value = caption;
    this.updateRatioNote();
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget || !this.textarea) return;
    const editing = !!this.blockAtCursor();
    const b = this.toggleButtonTarget;
    b.textContent = editing ? "Edit Gallery" : "Gallery";
    b.classList.toggle("bg-amber-100", editing);
    b.classList.toggle("hover:bg-amber-200", editing);
    b.classList.toggle("border-amber-700", editing);
    b.classList.toggle("text-amber-900", editing);
    b.classList.toggle("bg-gray-200", !editing);
    b.classList.toggle("hover:bg-gray-300", !editing);
    b.classList.toggle("border-gray-800", !editing);
  }

  pickImages(event) {
    event?.preventDefault();
    // The picker is a full-screen modal, so every click in it is "outside" this
    // popover. Suspend that check rather than closing and reopening — the
    // popover keeps its controls and its captured selection.
    this.pickerOpen = true;
    this.element.dispatchEvent(
      new CustomEvent("gallery-builder:pick-images", { bubbles: true }),
    );
  }

  addImages(mediaItems) {
    const known = new Set(this.images.map((image) => image.path));
    mediaItems.forEach(({ path, filename }) => {
      if (!path || known.has(path)) return; // re-picking one already listed
      known.add(path);
      this.images.push({ path, alt: filename || "", caption: "" });
    });

    this.show();
  }

  clearImages(event) {
    event?.preventDefault();
    this.images = [];
    this.fromSelection = false;
    this.renderImages();
  }

  // Filenames, plus a caption where one came in with the image. Captions
  // survive a round trip through here, but showing only the filename made that
  // impossible to tell from having lost them.
  renderImages() {
    if (!this.hasImageListTarget) return;
    const any = this.images.length > 0;

    this.imageListTarget.classList.toggle("hidden", !any);
    if (this.hasClearTarget) this.clearTarget.classList.toggle("hidden", !any);
    if (this.hasAddImagesTarget) {
      this.addImagesTarget.textContent = any ? "Add More" : "Add Images";
    }
    if (!any) return;

    this.imageListTarget.innerHTML = this.images
      .map((image) => {
        const name = this.escape(image.path.split("/").pop());
        const caption = image.caption
          ? `<span class="text-gray-500 italic"> — ${this.escape(image.caption)}</span>`
          : "";
        return `<div class="px-2 py-1 border-b border-gray-200 last:border-b-0 truncate text-gray-700">${name}${caption}</div>`;
      })
      .join("");
  }

  // --- inserting ------------------------------------------------------------

  // Carousels size images by height, so the aspect-ratio class is a no-op
  // there. Warn when both are set rather than silently dropping one.
  updateRatioNote() {
    if (!this.hasRatioNoteTarget) return;
    const carousel = this.hasCarouselTarget && this.carouselTarget.checked;
    const aspect = this.hasAspectTarget && this.aspectTarget.value;
    this.ratioNoteTarget.classList.toggle("hidden", !(carousel && aspect));
  }

  directives() {
    const out = [];
    if (this.hasCarouselTarget && this.carouselTarget.checked) {
      out.push("slideshow: true");
    }
    if (this.hasAspectTarget && this.aspectTarget.value) {
      out.push("aspect_ratio: " + this.aspectTarget.value);
    }
    // `caption:` is line-based, so collapse any stray whitespace.
    const caption = this.hasCaptionTarget ? this.captionTarget.value.trim() : "";
    if (caption) out.push("caption: " + caption.replace(/\s+/g, " "));
    return out;
  }

  imageLine({ path, alt, caption }) {
    return `![${alt}](${path})` + (caption ? `(*${caption}*)` : "");
  }

  reset() {
    if (this.hasCarouselTarget) this.carouselTarget.checked = false;
    if (this.hasAspectTarget) this.aspectTarget.value = "";
    if (this.hasCaptionTarget) this.captionTarget.value = "";
    this.images = [];
    this.fromSelection = false;
    this.editing = null;
    this.updateRatioNote();
    this.renderImages();
  }

  insert(event) {
    event?.preventDefault();

    const directives = this.directives();
    const images = this.images.map((image) => this.imageLine(image));
    const fromSelection = this.fromSelection;
    const editing = this.editing;

    this.reset();
    this.hide();
    if (!this.textarea) return;

    this.textarea.focus({ preventScroll: true });

    // Editing an existing block: rebuild it with the loaded/edited images and
    // directives and replace its whole line range in place, keeping the fence's
    // original indent. An emptied gallery still writes a placeholder so the
    // block stays valid and re-editable.
    if (editing) {
      const indent = editing.indent;
      const line = (text) => (text ? indent + text : "");
      const body = images.length > 0
        ? [ ...images, ...directives ].map(line)
        : [ line("__PLACEHOLDER__"), ...directives.map(line) ];
      const block = this.block(indent, body);

      const all = this.textarea.value.split("\n");
      const from = all.slice(0, editing.start).join("\n").length + (editing.start > 0 ? 1 : 0);
      const to = all.slice(0, editing.finish + 1).join("\n").length;
      this.textarea.setSelectionRange(from, to);
      document.execCommand("insertText", false, block);

      if (images.length === 0) {
        const idx = block.indexOf("__PLACEHOLDER__");
        if (idx !== -1) {
          this.textarea.setSelectionRange(from + idx, from + idx + "__PLACEHOLDER__".length);
        }
      } else {
        const pos = from + block.length;
        this.textarea.setSelectionRange(pos, pos);
      }
      this.updateToggleButton();
      return;
    }

    const start = this.savedStart ?? this.textarea.selectionStart;
    const end = this.savedEnd ?? this.textarea.selectionEnd;
    const hasSelection = start !== null && end !== null && start !== end;

    const { indent, lineStart, needsBreak } = this.blockContext(start);
    const line = (text) => (text ? indent + text : "");

    let body;
    if (images.length > 0) {
      body = [ ...images, ...directives ].map(line);
    } else if (hasSelection) {
      // Nothing recognised in what was highlighted, so it's wrapped as written.
      body = [
        this.textarea.value
          .substring(start, end)
          .split("\n")
          .map((text) => line(text.trim()))
          .join("\n"),
        ...directives.map(line),
      ];
    } else {
      body = [ line("__PLACEHOLDER__"), ...directives.map(line) ];
    }

    const block = this.block(indent, body);
    const replacing = hasSelection && (images.length === 0 || fromSelection);

    // Three ways in, and the difference is only ever about the line the block
    // has to start on:
    //   replacing  — the selection stands in for it
    //   needsBreak — there's text on this line already, so open a new one
    //   otherwise  — take the line from its start, swallowing any indent
    //                already typed there so the block supplies its own
    let from = lineStart;
    let to = start;
    if (replacing) {
      from = start;
      to = end;
    } else if (needsBreak) {
      from = start;
      to = start;
    }

    const text = needsBreak ? "\n" + block : block;
    this.textarea.setSelectionRange(from, to);
    document.execCommand("insertText", false, text);

    // Select the placeholder so the author can immediately add images.
    if (images.length === 0 && !hasSelection) {
      const idx = text.indexOf("__PLACEHOLDER__");
      if (idx !== -1) {
        this.textarea.setSelectionRange(
          from + idx,
          from + idx + "__PLACEHOLDER__".length,
        );
      }
    }
    this.updateToggleButton();
  }

  blockContext(start) {
    const value = this.textarea.value;
    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    const lineEnd = value.indexOf("\n", lineStart);
    const line = value.substring(
      lineStart,
      lineEnd === -1 ? value.length : lineEnd,
    );

    return {
      lineStart,
      // A fence has to begin a line, or whatever is already on this one runs
      // straight into it: `[^1]: ```gallery`.
      needsBreak: value.substring(lineStart, start).trim() !== "",
      indent: this.blockIndent(value, lineStart, line),
    };
  }

  // How far a block written here has to be indented to stay where it was put.
  //
  // A footnote's continuation is indented four spaces and kramdown ejects
  // anything less back out to the body — which is how a gallery ended up below
  // the footnotes section instead of inside the note. Reading the indentation
  // of the current line isn't enough: the definition line itself starts at
  // column zero, and says nothing about what has to follow it.
  blockIndent(value, lineStart, line) {
    if (this.constructor.FOOTNOTE_DEF_RE.test(line)) return "    ";

    const own = (line.match(/^ */) || [ "" ])[0];
    if (own.length >= 4) return own;

    // Unindented — but a footnote's continuation may still be above us, with
    // the editor not having carried the indent onto this line.
    let idx = lineStart;
    while (idx > 0) {
      const previousEnd = idx - 1;
      const previousStart = value.lastIndexOf("\n", previousEnd - 1) + 1;
      const previous = value.substring(previousStart, previousEnd);

      // A blank line above an unindented one ends the footnote; four spaces
      // carry it on; anything else is ordinary body text.
      if (previous.trim() === "") return "";
      if (this.constructor.FOOTNOTE_DEF_RE.test(previous)) return "    ";
      if (!/^ {4}/.test(previous)) return "";
      idx = previousStart;
    }
    return "";
  }

  block(indent, lines) {
    return indent + "```gallery\n" + lines.join("\n") + "\n" + indent + "```";
  }

  escape(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}

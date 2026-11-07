import { Controller } from "@hotwired/stimulus";

// Tab indents in a plain-text textarea instead of leaving it.
//
//   Tab                 inserts two spaces at the caret
//   Tab on a selection  indents every selected line by two spaces
//   Shift-Tab           removes up to two leading spaces (or a tab) from the
//                       caret's line, or every selected line
//   Esc, then Tab       leaves the textarea as usual, so keyboard users
//                       aren't trapped in it
//
// Edits go through execCommand("insertText"), so ⌘Z undoes them and an
// `input` event fires like any typing.
export default class extends Controller {
  static INDENT = "  ";

  connect() {
    this.escaped = false;
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.escaped = true;
      return;
    }
    if (event.key !== "Tab" || event.metaKey || event.ctrlKey || event.altKey) {
      this.escaped = false;
      return;
    }
    if (this.escaped) {
      this.escaped = false;
      return; // let Tab move focus
    }

    event.preventDefault();
    const field = this.element;
    const { selectionStart: start, selectionEnd: end, value } = field;
    const multiline = value.slice(start, end).includes("\n");

    if (!event.shiftKey && !multiline) {
      this.replace(start, end, this.constructor.INDENT);
      return;
    }

    // Whole lines touched by the selection (a selection ending at the very
    // start of a line doesn't include that line).
    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    let lineEnd = value.indexOf("\n", end > start && value[end - 1] === "\n" ? end - 1 : end);
    if (lineEnd === -1) lineEnd = value.length;

    const lines = value.slice(lineStart, lineEnd).split("\n");
    const changed = lines.map((line) => (event.shiftKey ? outdent(line) : this.constructor.INDENT + line));
    const text = changed.join("\n");
    if (text === lines.join("\n")) return;

    this.replace(lineStart, lineEnd, text);
    // Keep the same lines selected; a caret stays a caret, moved with its line.
    const firstShift = changed[0].length - lines[0].length;
    const newStart = Math.max(lineStart, start + firstShift);
    if (start === end) {
      field.setSelectionRange(newStart, newStart);
    } else {
      field.setSelectionRange(newStart, end + (text.length - (lineEnd - lineStart)));
    }
  }

  replace(from, to, text) {
    const field = this.element;
    field.focus();
    field.setSelectionRange(from, to);
    if (!document.execCommand("insertText", false, text)) {
      field.setRangeText(text, from, to, "end");
      field.dispatchEvent(new Event("input", { bubbles: true }));
    }
  }
}

function outdent(line) {
  if (line.startsWith("\t")) return line.slice(1);
  return line.replace(/^ {1,2}/, "");
}

import { Controller } from "@hotwired/stimulus";

// Box buttons for the layout editor. A click adds `[box]` at the caret:
//
//   caret on an empty line   → `[box]`, indented like the block's other
//                              rows (see indentFor)
//   caret on a line of boxes → ` [box] `, with a space either side only
//                              where there isn't one already
//   caret inside a box       → after that box, not in the middle of it
//   never clicked into yet   → on a new line at the end, indented the same
//                              way
//
// The caret ends up just after the new box, and the edit goes through
// execCommand("insertText"), so ⌘Z undoes it and the live help updates.
// Buttons for boxes already in the layout are greyed out (data-used), and
// [body] is disabled once there, since a layout has one.
export default class extends Controller {
  static targets = ["input", "button"];

  connect() {
    this.touched = false;
    this.onFocus = () => (this.touched = true);
    this.onInput = () => this.markUsed();
    this.inputTarget.addEventListener("focus", this.onFocus);
    this.inputTarget.addEventListener("input", this.onInput);
    this.markUsed();
  }

  disconnect() {
    this.inputTarget.removeEventListener("focus", this.onFocus);
    this.inputTarget.removeEventListener("input", this.onInput);
  }

  add(event) {
    const box = `[${event.currentTarget.dataset.box.replace(/_/g, " ")}]`;
    const field = this.inputTarget;
    const value = field.value;

    if (!this.touched) {
      const lines = value.replace(/\n$/, "").split("\n");
      const indent = indentFor(lines, lines.length);
      const lead = value === "" || value.endsWith("\n") ? "" : "\n";
      this.insert(value.length, value.length, lead + indent + box);
      return;
    }

    let at = field.selectionEnd;
    const lineStart = value.lastIndexOf("\n", at - 1) + 1;
    let lineEnd = value.indexOf("\n", at);
    if (lineEnd === -1) lineEnd = value.length;
    const line = value.slice(lineStart, lineEnd);

    // An empty line (or only spaces): the box starts a row at the end of
    // the block above, indented like its rows. A blank line between two
    // blocks stays, so they don't merge.
    if (line.trim() === "") {
      const lines = value.split("\n");
      const index = value.slice(0, lineStart).split("\n").length - 1;
      const between = index > 0 && lines[index - 1].trim() !== "" && index + 1 < lines.length && lines[index + 1].trim() !== "";
      const text = indentFor(lines, index) + box;
      this.insert(lineStart, lineEnd, between ? text + "\n" : text, between ? -1 : 0);
      return;
    }

    // Before the line's text? Start after its indentation.
    const leading = line.match(/^[ \t]*/)[0].length;
    if (at - lineStart < leading) at = lineStart + leading;

    // Inside a box? Move past its closing bracket.
    const beforeOnLine = value.slice(lineStart, at);
    if (beforeOnLine.lastIndexOf("[") > beforeOnLine.lastIndexOf("]")) {
      const close = value.indexOf("]", at);
      if (close !== -1 && close < lineEnd) at = close + 1;
    }

    const before = value.slice(lineStart, at);
    const after = value.slice(at, lineEnd);
    let text = box;
    if (before.trim() !== "" && !/\s$/.test(before)) text = " " + text;
    if (after.trim() !== "" && !/^\s/.test(after)) text = text + " ";
    this.insert(at, at, text, text.endsWith(" ") ? -1 : 0);
  }

  // Replace from..to with text; leave the caret after the box (back one if
  // a trailing space was added).
  insert(from, to, text, caretOffset = 0) {
    const field = this.inputTarget;
    field.focus();
    field.setSelectionRange(from, to);
    if (!document.execCommand("insertText", false, text)) {
      field.setRangeText(text, from, to, "end");
      field.dispatchEvent(new Event("input", { bubbles: true }));
    }
    const caret = from + text.length + caretOffset;
    field.setSelectionRange(caret, caret);
    this.touched = true;
  }

  markUsed() {
    const used = new Set(
      [...this.inputTarget.value.matchAll(/\[([^\[\]]*)\]/g)].map((m) => m[1].trim().toLowerCase().replace(/\s+/g, "_")),
    );
    this.buttonTargets.forEach((button) => {
      const isUsed = used.has(button.dataset.box);
      button.dataset.used = isUsed;
      button.disabled = isUsed && button.dataset.box === "body";
    });
  }
}

// A line that's only a block's name (`post-header:`).
const NAME_LINE = /^\s*[^\[\]:]+:\s*$/;

// The indentation a new row at `index` should have, joining the block
// above it: the same as the row just above; under a block's name, the
// indentation other named blocks give their rows (none if they're flat).
// Nothing above, or a blank line: a new block, at the left edge. The same
// convention ContentLayout.tidy keeps on save.
function indentFor(lines, index) {
  const above = index > 0 ? lines[index - 1] : "";
  if (above.trim() === "") return "";
  if (NAME_LINE.test(above)) return namedRowIndent(lines);
  return above.match(/^[ \t]*/)[0];
}

// How rows under a name are indented elsewhere in the layout.
function namedRowIndent(lines) {
  for (let i = 0; i < lines.length - 1; i++) {
    const isFirstOfBlock = i === 0 || lines[i - 1].trim() === "";
    if (isFirstOfBlock && NAME_LINE.test(lines[i]) && lines[i + 1].trim() !== "") {
      const indent = lines[i + 1].match(/^[ \t]*/)[0];
      if (indent) return indent;
    }
  }
  return "";
}

import { Controller } from "@hotwired/stimulus";

// Box buttons for the layout editor. A click adds `[box]` at the caret:
//
//   caret on an empty line   → `[box]`
//   caret on a line of boxes → ` [box] `, with a space either side only
//                              where there isn't one already
//   caret inside a box       → after that box, not in the middle of it
//   never clicked into yet   → on a new line at the end
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

    let at = this.touched ? field.selectionEnd : value.length;
    if (!this.touched && value.length && !value.endsWith("\n")) {
      this.insert(value.length, "\n" + box);
      return;
    }

    // Inside a box? Move past its closing bracket.
    const lineStart = value.lastIndexOf("\n", at - 1) + 1;
    let lineEnd = value.indexOf("\n", at);
    if (lineEnd === -1) lineEnd = value.length;
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
    this.insert(at, text, text.endsWith(" ") ? -1 : 0);
  }

  // Insert at `at`; leave the caret after the box (back one if a trailing
  // space was added).
  insert(at, text, caretOffset = 0) {
    const field = this.inputTarget;
    field.focus();
    field.setSelectionRange(at, at);
    if (!document.execCommand("insertText", false, text)) {
      field.setRangeText(text, at, at, "end");
      field.dispatchEvent(new Event("input", { bubbles: true }));
    }
    const caret = at + text.length + caretOffset;
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

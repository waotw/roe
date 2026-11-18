import { Controller } from "@hotwired/stimulus";

// A metadata value that can run to more than one line — a custom field, or a
// subtitle — is a text input until it has a line break, then a textarea, and
// back to a text input when the last break goes. The value saves as written,
// line breaks included (a `|-` block in the front matter).
//
//   Shift-Enter in the input     starts a new line (a plain Enter in an
//                                input doesn't, so it keeps doing whatever
//                                it did before)
//   pasting text with lines      keeps them, where an input would drop them
//   deleting the last line break turns it back into an input
//
// Sits on the fields container and listens for events from the fields marked
// `data-multiline`, so rows added or rebuilt later work without wiring. The
// new element takes the old one's attributes; `swapped` fires before its
// `input`, so the metadata editor can listen to it before it hears the change.
export default class extends Controller {
  keydown(event) {
    const field = this.multiline(event.target);
    if (!field || field.tagName === "TEXTAREA") return;
    if (event.key !== "Enter" || !event.shiftKey || event.isComposing) return;

    event.preventDefault();
    this.insert(field, "\n");
  }

  paste(event) {
    const field = this.multiline(event.target);
    if (!field || field.tagName === "TEXTAREA") return;

    const text = event.clipboardData?.getData("text/plain") || "";
    if (!/[\r\n]/.test(text)) return;

    event.preventDefault();
    this.insert(field, text.replace(/\r\n?/g, "\n"));
  }

  input(event) {
    const field = this.multiline(event.target);
    if (!field || field.tagName !== "TEXTAREA") return;

    if (field.value.includes("\n")) {
      this.fit(field);
    } else {
      this.swap(field, field.value, field.selectionStart, field.selectionEnd);
    }
  }

  multiline(target) {
    return target instanceof HTMLElement && target.matches("[data-multiline]")
      ? target
      : null;
  }

  insert(field, text) {
    const start = field.selectionStart ?? field.value.length;
    const end = field.selectionEnd ?? start;
    const value = field.value.slice(0, start) + text + field.value.slice(end);
    const caret = start + text.length;
    this.swap(field, value, caret, caret);
  }

  swap(field, value, start, end) {
    const lines = value.includes("\n");
    const next = document.createElement(lines ? "textarea" : "input");
    for (const { name, value: attr } of Array.from(field.attributes)) {
      if (name !== "type" && name !== "value" && name !== "rows") {
        next.setAttribute(name, attr);
      }
    }
    if (!lines) next.type = "text";
    next.value = value;
    if (lines) this.fit(next);

    field.replaceWith(next);
    next.focus();
    next.setSelectionRange(start, end);

    this.dispatch("swapped", { detail: { field: next } });
    next.dispatchEvent(new Event("input", { bubbles: true }));
  }

  // As many rows as it has lines, so the whole value shows.
  fit(field) {
    field.rows = Math.max(2, field.value.split("\n").length);
  }
}

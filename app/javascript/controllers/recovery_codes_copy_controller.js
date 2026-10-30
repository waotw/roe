import { Controller } from "@hotwired/stimulus";
import { copyToClipboard } from "clipboard";

// Copy the recovery codes exactly as shown — one per line, no stray
// whitespace — and confirm on the Generate button by swapping its label to
// "Copied" for a beat without changing its colour.
//
// Why its own controller and not the generic `clipboard` one: here the thing
// you click to copy (the codes block) is not the thing that shows feedback
// (the Generate button), and we must NOT disable the button or dim it — the
// ask was "switch to Copied (same colour) for a second". The payload is read
// from the codes element's data attribute so the copied text is the canonical
// newline-joined list, never a browser's mangled selection.
//
// Use:
//   <div data-controller="recovery-codes-copy">
//     <code data-recovery-codes-copy-target="codes"
//           data-recovery-codes-copy-text-value="CODE-1\nCODE-2"
//           data-action="click->recovery-codes-copy#copy">…</code>
//     <button data-recovery-codes-copy-target="feedback"
//             data-action="click->recovery-codes-copy#copy">Generate…</button>
//   </div>
export default class extends Controller {
  static targets = ["codes", "feedback"];
  static values  = {
    text:         String,
    copiedLabel:  { type: String, default: "Copied" },
    revertAfter:  { type: Number, default: 1200 },
  };

  async copy(event) {
    // The Generate button is a form submit; copying must not submit it.
    event.preventDefault();

    const text = this.payload();
    if (!text) return;

    try {
      await copyToClipboard(text);
      this.flash(this.copiedLabelValue);
    } catch (e) {
      console.warn("[recovery-codes-copy] copy failed:", e);
      this.flash("Press ⌘/Ctrl-C");
    }
  }

  // Prefer the explicit value (exact newline-joined list); fall back to the
  // codes element's text so a missing value still copies something sane.
  payload() {
    if (this.hasTextValue && this.textValue) return this.textValue;
    if (this.hasCodesTarget) return this.codesTarget.textContent;
    return null;
  }

  // Swap the label only — no disabled, no colour change — then restore it.
  // Guard against a double-click stacking timers or capturing "Copied" as
  // the original label.
  flash(label) {
    if (!this.hasFeedbackTarget) return;
    const button = this.feedbackTarget;

    if (this._revert) {
      clearTimeout(this._revert);
    } else {
      this._original = button.textContent;
    }

    button.textContent = label;
    this._revert = setTimeout(() => {
      button.textContent = this._original;
      this._revert = null;
    }, this.revertAfterValue);
  }

  disconnect() {
    if (this._revert) clearTimeout(this._revert);
  }
}

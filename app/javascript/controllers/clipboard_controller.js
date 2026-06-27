import { Controller } from "@hotwired/stimulus";

// Copy a value to the clipboard and flash a quick "Copied" label on
// the triggering button. Two ways to supply the value:
//
//   1. A `source` target whose `value` (input) or `textContent`
//      (anything else) becomes the payload. Best when the text is
//      already in the DOM you'd want to show.
//   2. A `data-clipboard-text-value` on the button itself, when the
//      payload is too long to render inline or contains markup.
//
// Use:
//   <div data-controller="clipboard"
//        data-clipboard-success-label-value="Copied">
//     <input data-clipboard-target="source" value="...">
//     <button data-clipboard-target="trigger"
//             data-action="click->clipboard#copy">Copy</button>
//   </div>
export default class extends Controller {
  static targets = ["source", "trigger"];
  static values  = {
    successLabel: { type: String, default: "Copied" },
    revertAfter:  { type: Number, default: 1500 },
  };

  async copy(event) {
    const button = event.currentTarget;
    const text = this.payloadFor(button);
    if (!text) return;

    try {
      await navigator.clipboard.writeText(text);
      this.flashSuccess(button);
    } catch (e) {
      console.warn("[clipboard] copy failed:", e);
    }
  }

  payloadFor(button) {
    if (button.dataset.clipboardTextValue) return button.dataset.clipboardTextValue;
    if (!this.hasSourceTarget) return null;
    const source = this.sourceTarget;
    return "value" in source ? source.value : source.textContent;
  }

  flashSuccess(button) {
    const original = button.textContent;
    button.textContent = this.successLabelValue;
    button.disabled = true;
    setTimeout(() => {
      button.textContent = original;
      button.disabled = false;
    }, this.revertAfterValue);
  }
}

import { Controller } from "@hotwired/stimulus";

// A stored secret (password, SSH key, key passphrase) shows as a green "added"
// badge with Update / Remove buttons instead of an empty input, so it's clear
// something is saved. Update reveals the field to enter a new value; Remove
// sets a hidden clear flag and submits the form so the server wipes the stored
// value — a blank field on its own just means "keep the current value". New /
// empty credentials render the field directly (no badge).
export default class extends Controller {
  static targets = ["field", "badge", "clearFlag"];

  reveal(event) {
    event.preventDefault();
    if (this.hasBadgeTarget) this.badgeTarget.classList.add("hidden");
    if (this.hasFieldTarget) {
      this.fieldTarget.classList.remove("hidden");
      const input = this.fieldTarget.querySelector("input, textarea");
      if (input) input.focus();
    }
  }

  remove(event) {
    event.preventDefault();
    if (!window.confirm("Remove the saved value? You can re-enter it later.")) return;
    if (this.hasClearFlagTarget) this.clearFlagTarget.value = "1";
    const form = this.element.closest("form");
    if (form) form.requestSubmit();
  }
}

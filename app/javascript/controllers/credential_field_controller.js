import { Controller } from "@hotwired/stimulus";

// A stored secret (password, SSH key, key passphrase) is shown as a green
// "added" badge with an Update button instead of an empty input, so it's
// clear something is saved. Clicking Update hides the badge and reveals the
// field. New/empty credentials render the field directly (no badge), so
// there's nothing to reveal.
export default class extends Controller {
  static targets = ["field", "badge"];

  reveal(event) {
    event.preventDefault();
    if (this.hasBadgeTarget) this.badgeTarget.classList.add("hidden");
    if (this.hasFieldTarget) {
      this.fieldTarget.classList.remove("hidden");
      const input = this.fieldTarget.querySelector("input, textarea");
      if (input) input.focus();
    }
  }
}

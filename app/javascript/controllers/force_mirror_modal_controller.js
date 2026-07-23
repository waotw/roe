import { Controller } from "@hotwired/stimulus";

// Custom confirm modal for the destructive "force mirror → live" action, so it
// matches the delete-page/post modal (an overlay with a typed confirmation)
// rather than the browser's native confirm dialog. Isolated to the Site Sync
// page. The confirm button stays disabled until the input reads exactly "LIVE".
export default class extends Controller {
  static targets = ["modal", "input", "confirm"];

  open() {
    this.modalTarget.classList.remove("hidden");
    this.inputTarget.value = "";
    this.confirmTarget.disabled = true;
    this.inputTarget.focus();
  }

  close() {
    this.modalTarget.classList.add("hidden");
  }

  // Close only when the backdrop itself is clicked, not the card inside it.
  backdrop(event) {
    if (event.target === this.modalTarget) this.close();
  }

  validate() {
    this.confirmTarget.disabled = this.inputTarget.value.trim() !== "LIVE";
  }

  submitIfValid(event) {
    if (this.inputTarget.value.trim() === "LIVE") {
      event.preventDefault();
      this.confirmTarget.form.requestSubmit();
    }
  }
}

import { Controller } from "@hotwired/stimulus";

// Confirms before an action that reloads the config page and would discard
// unsaved edits — seeding a show from RSS, deleting an entry, disabling a
// feature.
//
// The config editor already guards `turbo:before-visit` and `beforeunload`,
// but neither fires for a form submission: Turbo emits turbo:submit-start, and
// a non-Turbo button_to does a full document POST that beforeunload treats as
// a normal navigation. So the buttons that rewrite the file were the one way
// out of the page with no warning at all.
//
// Click to confirm, no typing — this is a "you'll lose what you typed"
// warning, not a destructive-action gate. The buttons that do delete things
// keep their own turbo_confirm on top.
export default class extends Controller {
  static targets = ["modal", "message"];

  connect() {
    this.pending = null;
  }

  // data-action="submit->config-guard#guard" on any form that navigates.
  guard(event) {
    if (!window.hasUnsavedChanges) return;

    event.preventDefault();
    this.pending = event.target;

    if (this.hasMessageTarget) {
      this.messageTarget.textContent =
        event.target.dataset.guardMessage ||
        "This reloads the page, so anything you've typed and not saved will be lost.";
    }
    this.modalTarget.classList.remove("hidden");
  }

  confirm() {
    const form = this.pending;
    this.close();
    if (!form) return;

    // Clear the flag first, or the editor's own turbo:before-visit guard
    // fires a second prompt on the redirect that follows.
    window.hasUnsavedChanges = false;
    form.requestSubmit();
  }

  cancel() {
    this.close();
  }

  backdrop(event) {
    if (event.target === this.modalTarget) this.close();
  }

  close() {
    this.modalTarget.classList.add("hidden");
    this.pending = null;
  }
}

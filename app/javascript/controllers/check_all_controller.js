import { Controller } from "@hotwired/stimulus"

// SELECT ALL / SELECT NONE for a list of checkboxes, e.g. one sync's files in
// Sync History: ticking every file and restoring undoes that whole sync.
export default class extends Controller {
  static targets = ["checkbox", "toggle"]

  connect() {
    this.update()
  }

  toggle(event) {
    event.preventDefault()
    const check = !this.allChecked()
    this.checkboxTargets.forEach((cb) => (cb.checked = check))
    this.update()
  }

  update() {
    if (!this.hasToggleTarget) return
    this.toggleTarget.textContent = this.allChecked() ? "SELECT NONE" : "SELECT ALL"
  }

  allChecked() {
    return this.checkboxTargets.length > 0 && this.checkboxTargets.every((cb) => cb.checked)
  }
}

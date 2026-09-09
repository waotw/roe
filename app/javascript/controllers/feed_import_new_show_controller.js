import { Controller } from "@hotwired/stimulus"

// Toggles the inline "add a new podcast show from this feed" panel on the
// Feed Imports preview. The panel is a sibling <form> (HTML forbids nested
// forms), so this controller sits on the card wrapping both forms.
export default class extends Controller {
  static targets = ["panel", "trigger", "title"]

  open(event) {
    event.preventDefault()
    this.panelTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) this.triggerTarget.classList.add("hidden")
    if (this.hasTitleTarget) this.titleTarget.focus()
  }

  close(event) {
    event.preventDefault()
    this.panelTarget.classList.add("hidden")
    if (this.hasTriggerTarget) this.triggerTarget.classList.remove("hidden")
  }
}

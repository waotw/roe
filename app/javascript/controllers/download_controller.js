import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["spinner", "button"]

  start(event) {
    // Show the spinner and update the button text
    // Don't prevent the form submission - let it continue normally
    this.spinnerTarget.classList.remove("hidden")
    this.buttonTarget.value = "Downloading..."
    // Form will submit normally after this action completes
  }
}

import { Controller } from "@hotwired/stimulus"

// The MANAGE TAGS window on Settings → Content. The tag manager loads into a
// lazy turbo frame the first time the window opens.
export default class extends Controller {
  static targets = ["dialog", "frame"]

  open(event) {
    event.preventDefault()
    if (this.hasFrameTarget && !this.frameTarget.src) {
      this.frameTarget.src = this.frameTarget.dataset.src
    } else if (this.hasFrameTarget) {
      this.frameTarget.reload()
    }
    this.dialogTarget.classList.remove("hidden")
    this.keydown = (e) => { if (e.key === "Escape" && !e.defaultPrevented) this.close() }
    document.addEventListener("keydown", this.keydown)
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.classList.add("hidden")
    if (this.keydown) document.removeEventListener("keydown", this.keydown)
  }

  // A click on the dimmed backdrop, not the window.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  disconnect() {
    if (this.keydown) document.removeEventListener("keydown", this.keydown)
  }
}

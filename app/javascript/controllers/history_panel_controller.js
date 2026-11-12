import { Controller } from "@hotwired/stimulus"

// Sync History: a file in a sync opens in the panel under the sync; clicking
// the same file again closes it. The open file's ▸ turns, as it does on a
// file's own history page.
export default class extends Controller {
  static targets = ["link", "frame"]

  toggle(event) {
    const link = event.currentTarget
    if (link.getAttribute("aria-expanded") === "true") {
      event.preventDefault()
      this.frameTarget.removeAttribute("src")
      this.frameTarget.innerHTML = ""
      this.mark(null)
    } else {
      this.mark(link)
    }
  }

  mark(open) {
    this.linkTargets.forEach((link) => {
      const on = link === open
      link.setAttribute("aria-expanded", on ? "true" : "false")
      link.classList.toggle("bg-blue-50", on)
      const arrow = link.querySelector("[data-arrow]")
      if (arrow) arrow.classList.toggle("rotate-90", on)
    })
  }
}

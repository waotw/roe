import { Controller } from "@hotwired/stimulus"

// The tag manager's table (admin/tags/index): search, and the inline rename
// form each row swaps in for its counts.
export default class extends Controller {
  static targets = ["row", "view", "renameForm", "search"]

  search() {
    const query = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = query !== "" && !row.dataset.tag.includes(query)
    })
  }

  rename(event) {
    const row = event.target.closest("[data-tag-manager-target='row']")
    this.rowTargets.forEach((other) => { if (other !== row) this.showView(other) })
    const view = row.querySelector("[data-tag-manager-target='view']")
    const form = row.querySelector("[data-tag-manager-target='renameForm']")
    view.classList.add("hidden")
    view.classList.remove("grid")
    form.classList.remove("hidden")
    form.classList.add("flex")
    const input = form.querySelector("input[name='to']")
    input.focus()
    input.select()
  }

  cancel(event) {
    event.preventDefault()
    this.showView(event.target.closest("[data-tag-manager-target='row']"))
  }

  showView(row) {
    const view = row.querySelector("[data-tag-manager-target='view']")
    const form = row.querySelector("[data-tag-manager-target='renameForm']")
    form.classList.add("hidden")
    form.classList.remove("flex")
    view.classList.remove("hidden")
    view.classList.add("grid")
    form.reset()
  }
}

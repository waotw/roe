import { Controller } from "@hotwired/stimulus"

// Search on a content list matches tags as well as titles. When it does, the
// matching tags show under the item's title as links to the list filtered by
// that tag — the same ?tag= filter the tag manager's counts use.
// Show/hide by swapping classes: `hidden` and a display class on one element
// leaves the winner to stylesheet order.
export default class extends Controller {
  static targets = ["search", "hits"]

  connect() {
    this.update()
  }

  update() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    this.hitsTargets.forEach((list) => {
      let shown = 0
      list.querySelectorAll("[data-tag]").forEach((link) => {
        const match = query !== "" && link.dataset.tag.includes(query)
        link.classList.toggle("hidden", !match)
        link.classList.toggle("inline-block", match)
        if (match) shown += 1
      })
      list.classList.toggle("hidden", shown === 0)
      list.classList.toggle("flex", shown > 0)
    })
  }
}

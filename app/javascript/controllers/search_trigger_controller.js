import { Controller } from "@hotwired/stimulus"

// Rendered in content by a ```search block or a collection with `search: true`.
// On click, opens the global site-search overlay pre-scoped, by dispatching a
// `site-search:open` event the header site-search controller listens for.
export default class extends Controller {
  static values = { scope: Object }

  open(event) {
    event?.preventDefault()
    window.dispatchEvent(new CustomEvent("site-search:open", {
      detail: { scope: this.scopeValue },
    }))
  }
}

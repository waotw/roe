import { Controller } from "@hotwired/stimulus"

// Focuses (and, via native focus, scrolls to) a specific config field when
// the page is opened with ?focus=<field> — e.g. the media browse page links
// "Used in: Site config → logo" to /admin/configs/site/edit?focus=logo so the
// author lands directly on the logo input, ready to edit.
export default class extends Controller {
  connect() {
    const field = new URLSearchParams(window.location.search).get("focus")
    if (!field) return

    // Config inputs are named config_fields[<field>]. Try an exact match
    // first, then a prefix match so nested keys (theme.x) still resolve.
    const input =
      this.element.querySelector(`[name="config_fields[${field}]"]`) ||
      this.element.querySelector(`[name^="config_fields[${field}"]`)
    if (!input) return

    // Defer so layout/toggles settle before we scroll into view.
    requestAnimationFrame(() => {
      input.focus({ preventScroll: false })
      input.scrollIntoView({ behavior: "smooth", block: "center" })

      // Brief highlight so it's obvious which field was targeted.
      input.classList.add("ring-2", "ring-blue-500", "ring-offset-1")
      setTimeout(() => {
        input.classList.remove("ring-2", "ring-blue-500", "ring-offset-1")
      }, 2500)
    })
  }
}

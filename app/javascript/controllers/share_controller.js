import { Controller } from "@hotwired/stimulus"

// Share button for posts/pages. A single "Share" trigger:
//   - Touch devices (native share available) → the OS share sheet, which hands
//     the reader every app they have (copy/email included).
//   - Desktop → reveals a small Copy link + Email menu (Esc / outside-click to
//     close). Desktop Safari/Chrome expose navigator.share, but a desktop share
//     sheet only reaches that OS's apps and reads as odd, so we don't use it.
//
// The shared URL is the page's <link rel="canonical"> (falling back to the
// current URL) and the title is og:title, so what's shared matches what unfurls
// on social — both overridable via data values. No trackers, no third-party
// scripts. Progressively enhanced: with no JS the menu is simply visible.
export default class extends Controller {
  static targets = ["trigger", "menu", "copy", "email", "feedback"]
  static values = { url: String, title: String, text: String }

  connect() {
    this.url = this.urlValue || this.canonicalUrl()
    this.title = this.titleValue || this.pageTitle()
    this.text = this.textValue || ""

    if (this.hasEmailTarget) {
      const subject = encodeURIComponent(this.title)
      const body = encodeURIComponent(this.url)
      this.emailTarget.setAttribute("href", `mailto:?subject=${subject}&body=${body}`)
    }

    this._onDocClick = (e) => { if (!this.element.contains(e.target)) this.close() }
    this._onKeydown = (e) => { if (e.key === "Escape") this.close() }

    // Enhance: show the trigger, collapse the menu behind it.
    if (this.hasTriggerTarget) this.triggerTarget.hidden = false
    this.close()
  }

  disconnect() {
    this.close()
  }

  // Single entry point on the trigger.
  toggle(event) {
    event.preventDefault()
    if (this.canNativeShare()) { this.native(); return }
    this.isOpen() ? this.close() : this.open()
  }

  open() {
    if (!this.hasMenuTarget) return
    this.menuTarget.hidden = false
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this._onDocClick)
    document.addEventListener("keydown", this._onKeydown)
    if (this.hasCopyTarget) this.copyTarget.focus()
  }

  close() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this._onDocClick)
    document.removeEventListener("keydown", this._onKeydown)
  }

  isOpen() {
    return this.hasMenuTarget && !this.menuTarget.hidden
  }

  async native() {
    const data = { title: this.title, url: this.url }
    if (this.text) data.text = this.text
    try {
      await navigator.share(data)
    } catch (e) {
      // AbortError = reader dismissed the sheet; ignore. Otherwise fall back to
      // copying so the action still does something.
      if (e && e.name !== "AbortError") this.writeClipboard()
    }
  }

  copy(event) {
    if (event) event.preventDefault()
    this.writeClipboard()
    this.close()
  }

  async writeClipboard() {
    try {
      await navigator.clipboard.writeText(this.url)
      this.flash("Copied!")
    } catch (e) {
      this.flash("Press ⌘/Ctrl-C to copy")
    }
  }

  flash(message) {
    if (!this.hasFeedbackTarget) return
    this.feedbackTarget.textContent = message
    clearTimeout(this._flashTimer)
    this._flashTimer = setTimeout(() => { this.feedbackTarget.textContent = "" }, 2000)
  }

  // Native share only on touch devices (a coarse primary pointer).
  canNativeShare() {
    return typeof navigator !== "undefined" &&
      typeof navigator.share === "function" &&
      typeof window.matchMedia === "function" &&
      window.matchMedia("(pointer: coarse)").matches
  }

  canonicalUrl() {
    const link = document.querySelector('link[rel="canonical"]')
    return (link && link.href) || window.location.href
  }

  pageTitle() {
    const og = document.querySelector('meta[property="og:title"]')
    return (og && og.content) || document.title || ""
  }
}

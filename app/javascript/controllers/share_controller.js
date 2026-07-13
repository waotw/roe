import { Controller } from "@hotwired/stimulus"

// Share button for posts/pages. Where the browser supports it (mobile + some
// desktop), a click opens the NATIVE share sheet — handing the reader every app
// they have installed — and the explicit Copy link + Email row is hidden since
// the sheet already includes them. Everywhere else, Copy link + Email are the
// fallback. The shared URL is the page's <link rel="canonical"> (falling back to
// the current URL) and the title is og:title, so what's shared matches what
// unfurls on social. Both are overridable via data values. No trackers, no
// third-party scripts.
export default class extends Controller {
  static targets = ["native", "copy", "email", "feedback"]
  static values = { url: String, title: String, text: String }

  connect() {
    this.url = this.urlValue || this.canonicalUrl()
    this.title = this.titleValue || this.pageTitle()
    this.text = this.textValue || ""

    // Fill the email link with the resolved canonical URL + title.
    if (this.hasEmailTarget) {
      const subject = encodeURIComponent(this.title)
      const body = encodeURIComponent(this.url)
      this.emailTarget.setAttribute("href", `mailto:?subject=${subject}&body=${body}`)
    }

    // Native share available → show it, hide the explicit copy/email row.
    if (this.canNativeShare() && this.hasNativeTarget) {
      this.nativeTarget.hidden = false
      if (this.hasCopyTarget) this.copyTarget.hidden = true
      if (this.hasEmailTarget) this.emailTarget.hidden = true
    }
  }

  async share(event) {
    event.preventDefault()
    const data = { title: this.title, url: this.url }
    if (this.text) data.text = this.text
    try {
      await navigator.share(data)
    } catch (e) {
      // AbortError = the reader dismissed the sheet; ignore. Otherwise fall
      // back to copying so the action still does something.
      if (e && e.name !== "AbortError") this.copy(event)
    }
  }

  async copy(event) {
    event.preventDefault()
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

  canNativeShare() {
    return typeof navigator !== "undefined" && typeof navigator.share === "function"
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

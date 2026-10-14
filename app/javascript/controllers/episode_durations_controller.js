import { Controller } from "@hotwired/stimulus"
import { mediaDuration } from "media_duration"

// Backfills a blank episode `duration` — the same read the editor does
// (media_duration.js: a file's metadata in the browser, a YouTube video's
// length from the server) — but in the background on the Posts list, a
// couple at a time and only when the page is idle, so it never blocks. Each
// item element is a podcast/audio/video row with no duration yet; once saved,
// future visits render nothing to do.
export default class extends Controller {
  static targets = ["item"]
  static values = { concurrency: { type: Number, default: 2 } }

  connect() {
    this.queue = [...this.itemTargets]
    this.running = 0
    if (this.queue.length === 0) return
    const start = () => this.pump()
    "requestIdleCallback" in window ? requestIdleCallback(start) : setTimeout(start, 500)
  }

  pump() {
    while (this.running < this.concurrencyValue && this.queue.length) {
      const item = this.queue.shift()
      this.running++
      this.process(item).finally(() => { this.running--; this.pump() })
    }
  }

  async process(item) {
    const { mediaUrl, saveUrl } = item.dataset
    if (!mediaUrl || !saveUrl) return

    let duration
    try {
      // A file is read in the browser; a YouTube link is looked up on the
      // server (media_duration.js).
      duration = await mediaDuration(mediaUrl)
    } catch (_e) {
      return // unreachable / unreadable — leave it blank
    }

    try {
      await fetch(saveUrl, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
        body: JSON.stringify({ duration })
      })
    } catch (_e) {
      // network hiccup — next visit will retry
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}

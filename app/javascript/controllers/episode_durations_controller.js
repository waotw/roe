import { Controller } from "@hotwired/stimulus"

// Backfills a blank episode `duration` from the browser — the same audio/video
// metadata read the editor does — but in the background on the Posts list, a
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
    const { mediaUrl, saveUrl, kind } = item.dataset
    if (!mediaUrl || !saveUrl) return

    let seconds
    try {
      seconds = await this.readDuration(mediaUrl, kind)
    } catch (_e) {
      return // unreachable / unreadable — leave it blank
    }
    if (!isFinite(seconds) || seconds <= 0) return

    try {
      await fetch(saveUrl, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
        body: JSON.stringify({ duration: this.format(Math.floor(seconds)) })
      })
    } catch (_e) {
      // network hiccup — next visit will retry
    }
  }

  readDuration(url, kind) {
    return new Promise((resolve, reject) => {
      const el = kind === "video" ? document.createElement("video") : new Audio()
      el.preload = "metadata"
      el.addEventListener("loadedmetadata", () => resolve(el.duration))
      el.addEventListener("error", () => reject(new Error("media load failed")))
      el.src = url
      el.load()
    })
  }

  // Matches media_field_controller.formatDuration (HH:MM:SS).
  format(seconds) {
    const h = String(Math.floor(seconds / 3600)).padStart(2, "0")
    const m = String(Math.floor((seconds % 3600) / 60)).padStart(2, "0")
    const s = String(seconds % 60).padStart(2, "0")
    return `${h}:${m}:${s}`
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}

import { Controller } from "@hotwired/stimulus"

// Polls the media-import status endpoint and updates the panel; reloads the
// page when the import finishes so the scan reflects what's now local.
export default class extends Controller {
  static values = { url: String }
  static targets = ["state", "detail"]

  connect() {
    this.poll()
    this.timer = setInterval(() => this.poll(), 2500)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      const s = await res.json()
      this.render(s)
      if (["done", "failed", "idle"].includes(s.state)) {
        clearInterval(this.timer)
        if (s.state === "done") setTimeout(() => location.reload(), 1200)
      }
    } catch (_e) {
      // keep the last rendered state
    }
  }

  render(s) {
    if (this.hasStateTarget) this.stateTarget.textContent = this.label(s)
    if (!this.hasDetailTarget) return

    const parts = []
    if (s.step === "rewriting" && s.records_total) {
      parts.push(`${s.records_done || 0}/${s.records_total} items updated`)
    } else if (s.total) {
      parts.push(`${s.downloaded || 0}/${s.total} downloaded`)
    }
    if (s.failed) parts.push(`${s.failed} failed`)
    this.detailTarget.textContent = parts.join(" · ")
  }

  label(s) {
    switch (s.state) {
      case "running":
        if (s.step === "scanning") return "Scanning content…"
        if (s.step === "rewriting") return "Updating references…"
        return "Downloading media…"
      case "done":
        return "Done — refreshing…"
      case "failed":
        return `Failed: ${s.error || "error"}`
      default:
        return ""
    }
  }
}

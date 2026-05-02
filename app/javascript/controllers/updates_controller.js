import { Controller } from "@hotwired/stimulus"

// Polls /admin/updates/status while an update is in progress and
// keeps the on-page progress bar / current-step text / log output in
// sync. When the update transitions out of in_progress (completed,
// rolled_back, or failed), reloads the page so the index re-renders
// the appropriate post-update state — there's no in-place rendering
// path for those states, only the in-progress one.
export default class extends Controller {
  static targets = ["progressBar", "currentStep", "log", "inProgressPanel"]

  connect() {
    // Only poll when an update is actually in progress. The panel
    // target is only present in the DOM when @in_progress was true at
    // page render — its absence means the index page is showing the
    // "no update happening" state and there's nothing to poll for.
    if (this.hasInProgressPanelTarget) {
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.poll()
    this.pollInterval = setInterval(() => this.poll(), 2000)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  async poll() {
    try {
      const response = await fetch("/admin/updates/status", {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return

      const data = await response.json()

      if (data.status === "in_progress") {
        this.updateProgress(data)
      } else {
        // Status moved off in_progress — reload to render the
        // completed/rolled_back/failed view variant.
        this.stopPolling()
        window.location.reload()
      }
    } catch (e) {
      // Network blip — keep polling, don't bail.
      console.warn("[updates] polling error:", e)
    }
  }

  updateProgress(data) {
    if (this.hasProgressBarTarget && data.progress != null) {
      this.progressBarTarget.style.width = `${data.progress}%`
    }
    if (this.hasCurrentStepTarget && data.step) {
      this.currentStepTarget.textContent = data.step
    }
    if (this.hasLogTarget && data.log) {
      this.logTarget.innerHTML = this.formatLog(data.log)
      // Keep newest log lines visible.
      this.logTarget.scrollTop = this.logTarget.scrollHeight
    }
  }

  formatLog(log) {
    // Mirror Rails simple_format: escape HTML, split paragraphs on
    // blank lines, single newlines become <br>. Escaping first
    // prevents log content (which is just raw strings) from being
    // interpreted as markup.
    const escaped = this.escapeHtml(log)
    return escaped
      .split(/\n\n+/)
      .map(para => `<p>${para.replace(/\n/g, "<br>")}</p>`)
      .join("")
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}

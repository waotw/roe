import { Controller } from "@hotwired/stimulus";

// Polls /admin/site_sync/transfer_status every 2 s while a push or pull
// is running and updates the in-place "Currently…" label. When the state
// leaves :running the page reloads so the server-rendered completed /
// failed / reassessment card takes over.
//
// Mirrors the deploy-polling half of controllers/updates_controller.js.
// Lives on the Site Sync page only; the in-progress panel carries the
// data-controller attribute, so connect() only fires when there's
// actually something to watch.
export default class extends Controller {
  static targets = [
    "step",
    "progress",
    "progressLabel",
    "progressBar",
  ];

  connect() {
    this.startPolling();
  }

  disconnect() {
    this.stopPolling();
  }

  startPolling() {
    this.poll();
    this.pollInterval = setInterval(() => this.poll(), 2000);
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  async poll() {
    try {
      const response = await fetch("/admin/site_sync/transfer_status", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) return;

      const data = await response.json();

      if (data.state === "running") {
        if (this.hasStepTarget && data.step_label) {
          this.stepTarget.textContent = data.step_label;
        }
        this.updateProgress(data.progress);
      } else {
        this.stopPolling();
        window.location.reload();
      }
    } catch (e) {
      console.warn("[site-sync] polling error:", e);
    }
  }

  updateProgress(progress) {
    if (!this.hasProgressTarget) return;

    if (!progress || !progress.total) {
      // Non-rsync step (or step transitioned). Hide until rsync starts
      // reporting again — leaving the old numbers on screen would be
      // misleading.
      this.progressTarget.hidden = true;
      return;
    }

    this.progressTarget.hidden = false;

    if (this.hasProgressLabelTarget) {
      this.progressLabelTarget.textContent =
        `${progress.completed} of ${progress.total} files transferred`;
    }

    if (this.hasProgressBarTarget) {
      const pct = progress.total > 0
        ? Math.round((progress.completed / progress.total) * 100)
        : 0;
      this.progressBarTarget.style.width = `${pct}%`;
    }
  }
}

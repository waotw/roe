import { Controller } from "@hotwired/stimulus";

// Polls /admin/site_sync/static/transfer_status every 2 s while an
// SFTP push is running and updates the "Currently…" label + the
// progress bar. When the state leaves :running the page reloads so
// the server-rendered completed / failed card takes over.
//
// Sibling to site_sync_controller.js — same shape, different endpoint
// and cache key. Both can be active on the Site Sync page at once
// (a /site push and a /static_site push could in theory run together,
// though in practice the user kicks them off one at a time).
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
      const response = await fetch("/admin/site_sync/static/transfer_status", {
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
      console.warn("[static-site-sync] polling error:", e);
    }
  }

  updateProgress(progress) {
    if (!this.hasProgressTarget) return;

    if (!progress || !progress.total) {
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

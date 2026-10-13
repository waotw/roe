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
      this.progressLabelTarget.textContent = progressText(progress);
    }

    if (this.hasProgressBarTarget) {
      // By bytes when we have them: a sync of one large video and four
      // small files is one big file's worth of waiting, not five steps.
      const [done, total] = progress.bytes_total
        ? [progress.bytes_done, progress.bytes_total]
        : [progress.completed, progress.total];
      const pct = total > 0 ? Math.round((done / total) * 100) : 0;
      this.progressBarTarget.style.width = `${pct}%`;
    }
  }
}

// Kept in step with the server-rendered label in
// admin/site_sync/index.html.erb, so the first paint and every poll read
// the same.
function progressText(progress) {
  const files = `${progress.completed} of ${progress.total} files`;
  if (!progress.bytes_total) return `${files} transferred`;

  return `${files} · ${humanSize(progress.bytes_done)} of ${humanSize(progress.bytes_total)} sent`;
}

// Matches Rails' number_to_human_size defaults (three significant digits,
// trailing zeros dropped), which the server-rendered label uses.
function humanSize(bytes) {
  const units = ["Bytes", "KB", "MB", "GB", "TB"];
  let value = bytes || 0;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const shown = unit === 0 ? Math.round(value) : Number(value.toPrecision(3));
  return `${shown} ${units[unit]}`;
}

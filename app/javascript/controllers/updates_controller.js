import { Controller } from "@hotwired/stimulus";

// Handles live polling for two independent long-running operations on
// the Updates & Deploy page:
//
//   Updates  — polls /admin/updates/status while a Roe update is running.
//              Targets: progressBar, currentStep, log, inProgressPanel
//
//   Deploy   — polls /admin/updates/deploy/status while a deploy is running.
//              Targets: deployInProgressPanel, deployLog
//
// Both pollers use the same 2-second interval and the same formatLog helper.
// When the operation leaves its in-progress state, the page is reloaded so
// the server-rendered completion / failure card is shown.
export default class extends Controller {
  static targets = [
    // Update targets (existing)
    "progressBar",
    "currentStep",
    "log",
    "inProgressPanel",
    // Deploy targets (new)
    "deployInProgressPanel",
    "deployLog",
  ];

  connect() {
    if (this.hasInProgressPanelTarget) this.startPolling();
    if (this.hasDeployInProgressPanelTarget) this.startDeployPolling();
  }

  disconnect() {
    this.stopPolling();
    this.stopDeployPolling();
  }

  // ── Roe update polling ─────────────────────────────────────────────────

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
      const response = await fetch("/admin/updates/status", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) return;

      const data = await response.json();

      if (data.status === "in_progress") {
        this.updateProgress(data);
      } else {
        this.stopPolling();
        window.location.reload();
      }
    } catch (e) {
      console.warn("[updates] polling error:", e);
    }
  }

  updateProgress(data) {
    if (this.hasProgressBarTarget && data.progress != null) {
      this.progressBarTarget.style.width = `${data.progress}%`;
    }
    if (this.hasCurrentStepTarget && data.step) {
      this.currentStepTarget.textContent = data.step;
    }
    if (this.hasLogTarget && data.log) {
      this.logTarget.innerHTML = this.formatLog(data.log);
      this.logTarget.scrollTop = this.logTarget.scrollHeight;
    }
  }

  // ── Deploy polling ─────────────────────────────────────────────────────

  startDeployPolling() {
    this.pollDeploy();
    this.deployPollInterval = setInterval(() => this.pollDeploy(), 2000);
  }

  stopDeployPolling() {
    if (this.deployPollInterval) {
      clearInterval(this.deployPollInterval);
      this.deployPollInterval = null;
    }
  }

  async pollDeploy() {
    try {
      const response = await fetch("/admin/updates/deploy/status", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) return;

      const data = await response.json();

      if (data.state === "running") {
        if (this.hasDeployLogTarget && data.log) {
          this.deployLogTarget.innerHTML = this.formatLog(data.log);
          this.deployLogTarget.scrollTop = this.deployLogTarget.scrollHeight;
        }
      } else {
        // completed or failed — reload to render the server-side card
        this.stopDeployPolling();
        window.location.reload();
      }
    } catch (e) {
      console.warn("[updates] deploy polling error:", e);
    }
  }

  // ── Pre-deploy git check ────────────────────────────────────────────────

  // Called by the Deploy button. Checks for uncommitted changes first;
  // if the tree is clean (or git isn't available) shows the standard
  // confirm and proceeds. If dirty, shows the git modal instead.
  async checkBeforeDeploy(event) {
    const btn = event.currentTarget;
    const deployUrl = btn.dataset.deployUrl;
    const deployInfo = btn.dataset.confirmMsg;

    let data;
    try {
      const res = await fetch("/admin/updates/git_status", {
        headers: { Accept: "application/json" },
      });
      if (!res.ok) {
        console.warn("[updates] git_status HTTP", res.status, res.statusText);
        data = { clean: true };
      } else {
        data = await res.json();
      }
    } catch (e) {
      console.warn("[updates] git_status fetch error:", e.message);
      data = { clean: true };
    }

    this.showDeployModal(data, deployUrl, deployInfo);
  }

  // Programmatically POSTs to the deploy URL (avoids needing a nested form).
  submitDeploy(url) {
    const csrf =
      document.querySelector('meta[name="csrf-token"]')?.content ?? "";
    const form = document.createElement("form");
    form.method = "POST";
    form.action = url;
    const token = document.createElement("input");
    token.type = "hidden";
    token.name = "authenticity_token";
    token.value = csrf;
    form.appendChild(token);
    document.body.appendChild(form);
    form.submit();
  }

  // Single modal for both clean and dirty states.
  // Clean: shows deploy description + Deploy button.
  // Dirty: shows changed file list + auto-commit or manual-commit options.
  // Refresh re-renders the modal in place — no browser confirm() anywhere.
  showDeployModal(data, deployUrl, deployInfo) {
    const existing = document.getElementById("deploy-git-modal");
    if (existing) existing.remove();

    const modal = document.createElement("div");
    modal.id = "deploy-git-modal";
    modal.className = "fixed inset-0 flex items-center justify-center z-50";
    modal.style.backgroundColor = "rgba(0,17,52,0.35)";

    if (data.clean || data.git_unavailable) {
      // ── Clean state ──────────────────────────────────────────────────────────────
      modal.innerHTML = `
        <div class="bg-white border-2 border-gray-900 p-8 max-w-lg w-full mx-4">
          <h2 class="text-2xl font-bold text-gray-900 mb-3">Deploy to Live Server</h2>
          <p class="text-gray-700 mb-6">${this.escapeHtml(deployInfo)}</p>
          <div class="flex gap-3">
            <button id="modal-deploy-btn"
              class="uppercase text-sm px-4 py-2.5 border border-gray-800 bg-blue-600 hover:bg-blue-700 text-white font-mono rounded-xs">
              Deploy
            </button>
            <button id="modal-cancel-btn"
              class="uppercase text-sm px-4 py-2.5 border border-gray-400 bg-gray-100 hover:bg-gray-200 text-gray-700 font-mono rounded-xs">
              Cancel
            </button>
          </div>
        </div>
      `;
    } else {
      // ── Dirty state ──────────────────────────────────────────────────────────────
      const plural = data.count === 1 ? "file has" : "files have";
      const overflow =
        data.count > 10
          ? `<li class="text-xs text-gray-400 italic">…and ${data.count - 10} more</li>`
          : "";
      const fileItems = data.changed
        .map(
          (f) =>
            `<li class="font-mono text-xs text-gray-700">${this.escapeHtml(f)}</li>`,
        )
        .join("");

      modal.innerHTML = `
        <div class="bg-white border-2 border-gray-900 p-8 max-w-lg w-full mx-4">
          <h2 class="text-2xl font-bold text-gray-900 mb-3">Uncommitted Changes</h2>
          <p class="text-gray-700 mb-4">
            ${data.count} ${plural} uncommitted changes that won’t be
            included in the deploy unless committed first.
          </p>
          <ul class="bg-gray-50 border border-gray-200 p-3 mb-6 space-y-1 max-h-40 overflow-y-auto">
            ${fileItems}${overflow}
          </ul>
          <div class="space-y-3">
            <button id="modal-deploy-btn"
              class="w-full uppercase text-sm px-4 py-2.5 border border-gray-800 bg-blue-600 hover:bg-blue-700 text-white font-mono rounded-xs">
              Auto-commit and deploy
            </button>
            <div class="flex items-center gap-3">
              <button id="git-refresh-btn"
                class="flex-none uppercase text-sm px-4 py-2 border border-gray-400 bg-gray-100 hover:bg-gray-200 font-mono rounded-xs">
                Refresh
              </button>
              <span class="text-xs text-gray-500">I’ve committed manually — check again</span>
            </div>
            <button id="modal-cancel-btn"
              class="w-full text-center text-sm text-gray-400 hover:text-gray-700 py-1">
              Cancel
            </button>
          </div>
        </div>
      `;
    }

    document.body.appendChild(modal);

    // Deploy / auto-commit-and-deploy
    document
      .getElementById("modal-deploy-btn")
      ?.addEventListener("click", () => {
        modal.remove();
        this.submitDeploy(deployUrl);
      });

    // Refresh — re-renders modal in place, no browser confirm
    document
      .getElementById("git-refresh-btn")
      ?.addEventListener("click", async () => {
        let fresh;
        try {
          const res = await fetch("/admin/updates/git_status", {
            headers: { Accept: "application/json" },
          });
          fresh = res.ok ? await res.json() : { clean: true };
        } catch (e) {
          fresh = { clean: true };
        }
        modal.remove();
        this.showDeployModal(fresh, deployUrl, deployInfo);
      });

    // Cancel / click outside
    document
      .getElementById("modal-cancel-btn")
      ?.addEventListener("click", () => modal.remove());
    modal.addEventListener("click", (e) => {
      if (e.target === modal) modal.remove();
    });
  }

  // ── Copy-to-clipboard for the post-update restart instructions ────────
  //
  // Wired up on the "Copy" buttons next to terminal commands in the
  // post-update success panel. Reads the command string from the
  // button's data-command attribute, drops it on the clipboard, then
  // flashes the button to "Copied!" for ~1.5s as visual confirmation.
  // Non-technical users on the beta — the audience the restart panel
  // is written for — really benefit from "click button" vs "select
  // text manually" when copying paths with spaces.
  async copyCommand(event) {
    const btn = event.currentTarget;
    const command = btn.dataset.command;
    if (!command) return;

    try {
      await navigator.clipboard.writeText(command);
      const originalText = btn.textContent;
      btn.textContent = "Copied!";
      btn.classList.add("bg-green-100", "border-green-500", "text-green-800");
      setTimeout(() => {
        btn.textContent = originalText;
        btn.classList.remove("bg-green-100", "border-green-500", "text-green-800");
      }, 1500);
    } catch (e) {
      // navigator.clipboard requires a secure context (HTTPS or localhost)
      // and a user gesture. localhost in dev should always satisfy both,
      // but fall back gracefully just in case.
      console.warn("[updates] clipboard write failed:", e.message);
      btn.textContent = "Select & copy manually";
    }
  }

  // ── Shared helpers ─────────────────────────────────────────────────────

  formatLog(log) {
    const escaped = this.escapeHtml(log);
    return escaped
      .split(/\n\n+/)
      .map((para) => `<p>${para.replace(/\n/g, "<br>")}</p>`)
      .join("");
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}

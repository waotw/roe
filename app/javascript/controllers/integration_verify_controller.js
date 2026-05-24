import { Controller } from "@hotwired/stimulus";

// Fires a verify request when the config page loads and updates
// a status indicator without a page reload.
//
// Usage:
//   <div data-controller="integration-verify"
//        data-integration-verify-url-value="/admin/stripe_config/verify"
//        data-integration-verify-verified-value="<%= @stripe_config.connected? %>"
//        data-integration-verify-verified-at-value="<%= @stripe_config.verified_at&.iso8601 %>">
//     <span data-integration-verify-target="status"></span>
//     <span data-integration-verify-target="timestamp"></span>
//   </div>

export default class extends Controller {
  static values = {
    url: String,
    verified: Boolean,
    verifiedAt: String,
  };

  static targets = ["status", "timestamp"];

  connect() {
    // Show last known state immediately
    this.renderStatus(this.verifiedValue, this.verifiedAtValue);

    // Then re-verify live in the background
    this.verify();
  }

  async verify() {
    if (!this.urlValue) return;

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
      });

      if (!response.ok) {
        this.renderStatus(false, null, "Server error during verification");
        return;
      }

      const data = await response.json();
      this.renderStatus(data.verified, data.verified_at, data.error);
    } catch (e) {
      this.renderStatus(false, null, "Network error — could not verify");
    }
  }

  renderStatus(verified, verifiedAt, error = null) {
    if (!this.hasStatusTarget) return;

    if (verified) {
      this.statusTarget.innerHTML = `
        <span class="inline-flex items-center gap-1 text-green-700 text-xs font-mono">
          <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>
          Connected
        </span>`;

      if (this.hasTimestampTarget && verifiedAt) {
        const date = new Date(verifiedAt);
        this.timestampTarget.textContent = `Last verified ${date.toLocaleTimeString()}`;
        this.timestampTarget.className = "text-xs text-gray-400 font-mono";
      }
    } else {
      this.statusTarget.innerHTML = `
        <span class="inline-flex items-center gap-1 text-red-700 text-xs font-mono">
          <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm-1-5a1 1 0 112 0v-4a1 1 0 10-2 0v4zm1-8a1 1 0 100 2 1 1 0 000-2z" clip-rule="evenodd"/>
          </svg>
          Not connected${error ? `: ${error}` : ""}
        </span>`;

      if (this.hasTimestampTarget) {
        this.timestampTarget.textContent = "";
      }
    }
  }
}

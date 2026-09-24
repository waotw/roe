import { Controller } from "@hotwired/stimulus";

// The on-demand webhook proof on the Email status panel (production). The
// "Send a test event" button POSTs normally (a button_to form) and the page
// reloads with a flash; when a test is already in flight (data-pending), this
// polls the status endpoint and flips the row to verified without a reload.
export default class extends Controller {
  static targets = ["result"];
  static values = { statusUrl: String };

  connect() {
    if (this.hasResultTarget && this.resultTarget.dataset.pending === "true") {
      this.startPolling();
    }
  }

  disconnect() {
    if (this._poll) clearInterval(this._poll);
  }

  startPolling() {
    let tries = 0;
    this._poll = setInterval(async () => {
      tries += 1;
      const res = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } });
      const data = await res.json();
      if (data.verified) {
        this.show('<span class="text-green-700">✓ Verified working — Postmark reached your site.</span>');
        clearInterval(this._poll);
      } else if (tries >= 20) {
        this.show('<span class="text-amber-700">Still waiting for Postmark\'s callback. It can take a minute; reload to check again.</span>');
        clearInterval(this._poll);
      }
    }, 3000);
  }

  show(html) {
    if (this.hasResultTarget) this.resultTarget.innerHTML = html;
  }
}

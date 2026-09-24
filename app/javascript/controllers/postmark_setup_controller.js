import { Controller } from "@hotwired/stimulus";

// "Have Roe set up your Postmark integration."
//
// Two steps behind one form. Paste the Account API token → #preview asks the
// server which non-default servers exist and what the sender signatures look
// like, WITHOUT creating anything. If named servers exist, we reveal a reuse
// choice; otherwise the run just creates the sandbox + live servers. Submitting
// the real form (#run, a normal POST) does the work; after it redirects, a
// poller watches for the async webhook ✓.
//
// Self-contained: it owns its panel and posts to its own endpoints, so the rest
// of edit_integration.html.erb is untouched.
export default class extends Controller {
  static targets = [
    "token", "preview", "reuse", "sandboxReuse", "liveReuse",
    "signatures", "error", "runButton",
  ];
  static values = {
    previewUrl: String,
  };

  // Step 1 — validate the token and discover servers/signatures.
  async preview(event) {
    event?.preventDefault();
    const token = this.tokenTarget.value.trim();
    this.clearError();
    if (!token) { this.showError("Enter your Postmark Account API token."); return; }

    const res = await fetch(this.previewUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        Accept: "application/json",
      },
      body: JSON.stringify({ account_token: token }),
    });
    const data = await res.json();
    if (!data.ok) { this.showError(data.error || "Postmark didn't accept that token."); return; }

    this.renderReuse(data.reusable || []);
    this.renderSignatures(data.signatures || []);
    if (this.hasPreviewTarget) this.previewTarget.hidden = false;
    if (this.hasRunButtonTarget) this.runButtonTarget.hidden = false;
  }

  // Only surface a reuse choice when non-default servers exist — otherwise the
  // run creates fresh servers and there's nothing to choose.
  renderReuse(servers) {
    if (!this.hasReuseTarget) return;
    if (servers.length === 0) { this.reuseTarget.hidden = true; return; }

    const options = (sel) => {
      sel.innerHTML = '<option value="">Create a new one</option>';
      servers.forEach((s) => {
        const o = document.createElement("option");
        o.value = s.id;
        o.textContent = `${s.name} (${s.delivery_type})`;
        sel.appendChild(o);
      });
    };
    if (this.hasSandboxReuseTarget) options(this.sandboxReuseTarget);
    if (this.hasLiveReuseTarget) options(this.liveReuseTarget);
    this.reuseTarget.hidden = false;
  }

  renderSignatures(sigs) {
    if (!this.hasSignaturesTarget) return;
    if (sigs.length === 0) {
      this.signaturesTarget.innerHTML =
        '<li class="text-amber-700">No sender signatures yet — add and confirm your From address in Postmark.</li>';
      return;
    }
    this.signaturesTarget.innerHTML = sigs.map((s) => {
      const mark = s.confirmed
        ? '<span class="text-green-700">✓ confirmed</span>'
        : '<span class="text-amber-700">pending confirmation</span>';
      return `<li><span class="font-mono">${this.escape(s.email)}</span> — ${mark}</li>`;
    }).join("");
  }

  showError(msg) {
    if (this.hasErrorTarget) { this.errorTarget.textContent = msg; this.errorTarget.hidden = false; }
  }
  clearError() {
    if (this.hasErrorTarget) { this.errorTarget.textContent = ""; this.errorTarget.hidden = true; }
  }
  escape(text) {
    const d = document.createElement("div");
    d.textContent = text;
    return d.innerHTML;
  }
}

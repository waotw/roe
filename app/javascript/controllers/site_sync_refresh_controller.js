import { Controller } from "@hotwired/stimulus";

// The Site Sync page opened with live's answer more than a minute old, so the
// server asked live again in the background (Exchange.refresh_if_stale). This
// waits for that answer and reloads the page to show it, instead of leaving
// the old one up until someone presses REFRESH SYNC STATUS.
//
// It asks every 2 seconds for up to 20, then stops quietly: live may be
// unreachable, and the page already says what it last knew. If anything on the
// page was edited first (a setting, a conflict choice), it shows its note
// instead of reloading over the edit.
export default class extends Controller {
  static targets = ["note"];
  static values = { url: String, since: Number };

  connect() {
    this.edited = false;
    this.onEdit = () => (this.edited = true);
    document.addEventListener("input", this.onEdit);
    document.addEventListener("change", this.onEdit);
    this.tries = 0;
    this.timer = setInterval(() => this.check(), 2000);
  }

  disconnect() {
    clearInterval(this.timer);
    document.removeEventListener("input", this.onEdit);
    document.removeEventListener("change", this.onEdit);
  }

  async check() {
    if (++this.tries > 10) return clearInterval(this.timer);
    let receivedAt;
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } });
      if (!response.ok) return;
      receivedAt = (await response.json()).received_at;
    } catch {
      return;
    }
    if (!receivedAt || receivedAt <= this.sinceValue) return;

    clearInterval(this.timer);
    if (this.edited) {
      this.noteTarget.hidden = false;
    } else {
      window.location.reload();
    }
  }
}

import { Controller } from "@hotwired/stimulus";

// Used by the publish modal's media fields (audio/video/image) to:
//   - Warn inline when the path doesn't resolve to a file under site/media/
//   - For audio/video, auto-populate a matching duration field
//
// Targets:
//   input    (required) — the text input holding the /media/... path
//   warning  (optional) — an element that gets shown when the file is missing
//   duration (optional) — a text input to receive the extracted duration
//
// Values:
//   kind — "audio" | "video" | "image"
export default class extends Controller {
  static targets = ["input", "warning", "duration"];
  static values = { kind: String };

  connect() {
    this._debounceTimer = null;
    if (this.hasInputTarget && this.inputTarget.value.trim()) {
      this.check();
    }
  }

  disconnect() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
  }

  // Called on input as the user types. Debounces the existence check so
  // we don't hammer the server on every keystroke. Duration extraction
  // is skipped here — it only runs on blur/change (see check()).
  checkDebounced() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    this._debounceTimer = setTimeout(() => {
      const path = this.hasInputTarget ? this.inputTarget.value.trim() : "";
      if (!path) {
        this.hideWarning();
        return;
      }
      this.validateExistence(path);
    }, 200);
  }

  // Called on blur / change on the input (via data-action). Full check
  // including duration extraction.
  async check() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer);
    const path = this.hasInputTarget ? this.inputTarget.value.trim() : "";

    if (!path) {
      this.hideWarning();
      return;
    }

    await this.validateExistence(path);
    await this.populateDuration(path);
  }

  async validateExistence(path) {
    try {
      const url = `/admin/medium/exists?path=${encodeURIComponent(path)}`;
      const response = await fetch(url, { headers: { Accept: "application/json" } });

      if (!response.ok) {
        this.hideWarning();
        return;
      }

      const data = await response.json();

      if (data.checked === false || data.exists) {
        this.hideWarning();
      } else {
        this.showWarning();
      }
    } catch (error) {
      console.warn("[media-field] existence check failed:", error);
      this.hideWarning();
    }
  }

  async populateDuration(path) {
    if (!this.hasDurationTarget) return;
    if (!["audio", "video"].includes(this.kindValue)) return;
    if (this.durationTarget.value.trim()) return; // don't clobber a value already there

    const ext = path.split(".").pop().toLowerCase();
    const isAudio = ["mp3", "m4a", "wav", "ogg", "flac", "aac"].includes(ext);
    const isVideo = ["mp4", "webm", "ogv", "mov", "avi", "mkv"].includes(ext);
    if (!isAudio && !isVideo) return;

    try {
      const mediaElement = isAudio ? new Audio() : document.createElement("video");
      const duration = await new Promise((resolve, reject) => {
        mediaElement.addEventListener("loadedmetadata", () => resolve(mediaElement.duration));
        mediaElement.addEventListener("error", () => reject(new Error("media load failed")));
        mediaElement.src = path;
        mediaElement.load();
      });

      this.durationTarget.value = this.formatDuration(Math.floor(duration));
    } catch (error) {
      // Silent — the existence warning already covers a missing file.
    }
  }

  formatDuration(seconds) {
    const h = String(Math.floor(seconds / 3600)).padStart(2, "0");
    const m = String(Math.floor((seconds % 3600) / 60)).padStart(2, "0");
    const s = String(seconds % 60).padStart(2, "0");
    return `${h}:${m}:${s}`;
  }

  showWarning() {
    if (this.hasWarningTarget) this.warningTarget.classList.remove("hidden");
    if (this.hasInputTarget) this.inputTarget.classList.add("border-red-400");
  }

  hideWarning() {
    if (this.hasWarningTarget) this.warningTarget.classList.add("hidden");
    if (this.hasInputTarget) this.inputTarget.classList.remove("border-red-400");
  }
}

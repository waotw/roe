import { Controller } from "@hotwired/stimulus";

// The progress window for a video upload. It looks like a terminal (amber
// on black, box-drawing bars) and shows, in turn:
//
//   ▸ OPTIMIZING three-benches.mp4
//   ⠹ loading  ████████████░░░░░░░░░░░░   48%     ← the file uploading
//
// then, once the server has it, how far along each web version is:
//
//     poster  ████████████████████████  done
//   ⠹ 720p    ███████████░░░░░░░░░░░░░   46%
//     1080p   ░░░░░░░░░░░░░░░░░░░░░░░░  waiting
//
// Closing it changes nothing: the work carries on in the background, the
// card in the grid keeps its own progress bar, and the Media Browser shows
// a notice once it's done. It keeps watching while the work goes on, even
// when closed, so that notice appears without a refresh: on finishing it
// dispatches "video-progress:finished" (media-upload shows the notice).
//
// Opened by media-upload: startUpload(name) the moment a video is picked,
// uploadProgress(fraction) as it uploads, then openFor({ id, name }) once
// the server has it. openFor is also how clicking an optimizing card
// reopens it.
export default class extends Controller {
  static targets = ["dialog", "name", "rows", "summary", "footer"];

  static BAR = 24;
  static POLL_MS = 1500;
  static POLL_CLOSED_MS = 4000;

  disconnect() {
    this.stop();
    this.stopSpinner();
  }

  // ── Uploading ──────────────────────────────────────────────────────

  // The moment a video is picked: open straight away with a loading bar.
  startUpload(name) {
    this.stop();
    this.id = null;
    this.uploading = true;
    this.uploadFraction = null;
    this.nameTarget.textContent = name;
    this.summaryTarget.textContent = "";
    this.footerTarget.hidden = false;
    this.show();
    this.drawUpload();
    this.startSpinner(() => this.uploading && this.drawUpload());
  }

  // 0..1 as the file goes up (null when the browser can't tell).
  uploadProgress(fraction) {
    this.uploadFraction = fraction;
    if (this.uploading) this.drawUpload();
  }

  // The upload failed: say so, plainly.
  uploadFailed(message) {
    this.uploading = false;
    this.stopSpinner();
    // COPY: modal upload-failed line
    this.rowsTarget.textContent = "✗ upload failed";
    this.summaryTarget.textContent = message || "Upload failed — please try again.";
    this.footerTarget.hidden = true;
  }

  drawUpload() {
    const f = this.uploadFraction;
    const spin = this.spinner();
    // COPY: modal uploading row
    if (f == null) {
      // Size unknown: a bouncing block instead of a percentage.
      const width = this.constructor.BAR;
      const pos = (this.frame || 0) % (width * 2 - 2);
      const at = pos < width ? pos : width * 2 - 2 - pos;
      const bar = "░".repeat(at) + "█" + "░".repeat(width - at - 1);
      this.rowsTarget.textContent = `${spin} loading  ${bar}`;
    } else {
      const pct = Math.min(100, Math.round(f * 100));
      const label = pct >= 100 ? "saving…" : `${String(pct).padStart(3)}%`;
      this.rowsTarget.textContent = `${spin} loading  ${this.bar(pct)}  ${label}`;
    }
  }

  // ── Optimizing ─────────────────────────────────────────────────────

  // Show (or bring back) the window for a video the server has.
  openFor({ id, name }) {
    const sameVideo = String(this.id) === String(id);
    this.uploading = false;
    this.id = id;
    this.nameTarget.textContent = name;
    if (!sameVideo) {
      this.rowsTarget.textContent = "  reading the video…";
      this.summaryTarget.textContent = "";
    }
    this.footerTarget.hidden = false;
    this.show();
    this.startSpinner(() => this.lastStatus && this.render(this.lastStatus));
    this.stop();
    this.poll();
  }

  show() {
    if (typeof this.dialogTarget.showModal === "function") {
      if (!this.dialogTarget.open) this.dialogTarget.showModal();
    } else {
      this.dialogTarget.setAttribute("open", "");
    }
  }

  // Closing only hides the window. Watching carries on (more slowly) so the
  // page still hears when the video is done.
  close() {
    if (this.dialogTarget.open) this.dialogTarget.close();
    this.stopSpinner();
  }

  // Click on the backdrop (the dialog element itself, outside the box).
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close();
  }

  stop() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  poll() {
    if (!this.id) return;
    const id = this.id;
    fetch(`/admin/medium/${id}/video_status`, { headers: { Accept: "application/json" } })
      .then((r) => (r.ok ? r.json() : null))
      .then((status) => {
        if (String(this.id) !== String(id)) return; // switched to another video
        if (!status) return this.again(this.constructor.POLL_MS * 2);
        this.lastStatus = status;
        if (this.dialogTarget.open) this.render(status);
        if (status.state === "optimizing") return this.again();
        this.finished(status);
      })
      .catch(() => this.again(this.constructor.POLL_MS * 2));
  }

  again(ms) {
    if (!this.element.isConnected) return;
    const wait = ms || (this.dialogTarget.open ? this.constructor.POLL_MS : this.constructor.POLL_CLOSED_MS);
    this.timer = setTimeout(() => this.poll(), wait);
  }

  // Done, failed, or nothing to do: stop watching and tell the page.
  finished(status) {
    this.stop();
    this.stopSpinner();
    if (status.state === "done" || status.state === "failed") {
      this.dispatch("finished", { detail: { id: status.id, state: status.state } });
    }
  }

  render(status) {
    const rows = (status.steps || []).map((step) => this.row(step));
    this.rowsTarget.textContent = rows.join("\n");

    // COPY: modal status lines
    if (status.state === "done") {
      this.summaryTarget.textContent = status.served_as_original
        ? "✓ Done — this video was already web-ready, so the original is served as it is."
        : `✓ Done — ${this.size(status.source && status.source.size)} → ${(status.outputs || [])
            .map((o) => `${o.name} ${this.size(o.size)}`)
            .join(" · ")}`;
      this.footerTarget.hidden = true;
    } else if (status.state === "failed") {
      this.summaryTarget.textContent = `✗ ${status.error || "Couldn't optimize this video."} The original will be served.`;
      this.footerTarget.hidden = true;
    } else if (status.state === "none") {
      this.summaryTarget.textContent = "This video isn't being optimized, so the original is served as it is.";
      this.footerTarget.hidden = true;
    } else {
      this.summaryTarget.textContent = `  overall ${String(status.percent).padStart(3)}%`;
    }
  }

  row(step) {
    const label = {
      done: "done",
      skipped: "not needed",
      running: `${String(step.percent).padStart(3)}%`,
      waiting: "waiting",
      failed: "failed",
    }[step.state];
    const spin = step.state === "running" ? this.spinner() : " ";
    return `${spin} ${step.label.padEnd(7)} ${this.bar(step.percent)}  ${label}`;
  }

  bar(percent) {
    const width = this.constructor.BAR;
    const filled = Math.round((Math.min(percent || 0, 100) / 100) * width);
    return "█".repeat(filled) + "░".repeat(width - filled);
  }

  // ── Spinner ────────────────────────────────────────────────────────

  // Redraws on its own so the spinner (and the bouncing upload bar) keeps
  // moving between server answers.
  startSpinner(redraw) {
    this.stopSpinner();
    this.spinTimer = setInterval(() => {
      if (this.dialogTarget.open) redraw();
    }, 120);
  }

  stopSpinner() {
    if (this.spinTimer) clearInterval(this.spinTimer);
    this.spinTimer = null;
  }

  spinner() {
    const frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
    this.frame = (this.frame || 0) + 1;
    return frames[this.frame % frames.length];
  }

  size(bytes) {
    if (!bytes && bytes !== 0) return "?";
    const units = ["B", "KB", "MB", "GB"];
    let n = bytes;
    let u = 0;
    while (n >= 1024 && u < units.length - 1) {
      n /= 1024;
      u += 1;
    }
    return `${n >= 10 || u === 0 ? Math.round(n) : n.toFixed(1)} ${units[u]}`;
  }
}

import { Controller } from "@hotwired/stimulus";

// The video window on the Media Browser: DETAILS on a video card (or
// CHANGE in the progress window) opens it. It shows the video's poster and
// what the video is, and offers two ways to choose another poster:
//
//   FRAME FROM THE VIDEO   play or scrub to a moment, USE THIS FRAME
//   IMAGE FROM MEDIA       pick an image from the library, USE THIS IMAGE
//
// Either choice saves at once (MediumController#poster). The window stays
// open, the button stays, and CANCEL becomes CLOSE, since there's nothing
// left to cancel. The new poster replaces the old one wherever this page
// shows it (the card, the progress window), found by data-video-poster.
export default class extends Controller {
  static targets = [
    "dialog", "body", "panel", "tab", "pane", "video", "scrub", "time", "play",
    "jump", "search", "image", "posterNow", "caption", "footnote", "pickedNote",
    "error", "closeButton", "useFrame", "useImage",
  ];

  // DETAILS on a card: data-video-details-id-param.
  open(event) {
    event.preventDefault();
    event.stopPropagation();
    this.load(event.params.id);
  }

  // CHANGE in the progress window ("video-progress:change-poster").
  openFromEvent(event) {
    if (event.detail && event.detail.id) this.load(event.detail.id);
  }

  async load(id) {
    this.picked = null;
    this.bodyTarget.innerHTML = '<div class="bg-white p-6 font-mono text-xs text-gray-500">loading…</div>';
    this.show();
    try {
      const response = await fetch(`/admin/medium/${id}/details`, { headers: { Accept: "text/html" } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      this.bodyTarget.innerHTML = await response.text();
    } catch (error) {
      // COPY: window couldn't load
      this.bodyTarget.innerHTML = '<div class="bg-white p-6 text-sm text-red-700">Couldn\'t open this video. Try again in a moment.</div>';
    }
  }

  show() {
    if (typeof this.dialogTarget.showModal === "function") {
      if (!this.dialogTarget.open) this.dialogTarget.showModal();
    } else {
      this.dialogTarget.setAttribute("open", "");
    }
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close();
  }

  // The dialog closed (CLOSE, ×, Escape, outside): stop the video.
  closed() {
    if (this.hasVideoTarget) this.videoTarget.pause();
  }

  // A click on the backdrop (the dialog element itself, outside the box).
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close();
  }

  // ← → step one frame, while the frame tab shows and nothing is being typed.
  key(event) {
    if (!this.hasVideoTarget || this.currentTab() !== "frame") return;
    if (event.target.closest("input, textarea")) return;
    if (event.key === "ArrowLeft") { event.preventDefault(); this.stepBack(); }
    if (event.key === "ArrowRight") { event.preventDefault(); this.stepForward(); }
    if (event.key === " ") { event.preventDefault(); this.togglePlay(); }
  }

  // ── Tabs ─────────────────────────────────────────────────────────────

  tab(event) {
    const name = event.currentTarget.dataset.tab;
    this.tabTargets.forEach((tab) => {
      const on = tab.dataset.tab === name;
      tab.classList.toggle("border-gray-900", on);
      tab.classList.toggle("font-bold", on);
      tab.classList.toggle("text-gray-900", on);
      tab.classList.toggle("border-transparent", !on);
      tab.classList.toggle("text-gray-500", !on);
    });
    [...this.paneTargets, ...this.footnoteTargets].forEach((el) => { el.hidden = el.dataset.tab !== name; });
    this.useFrameTarget.hidden = name !== "frame";
    this.useImageTarget.hidden = name !== "image";
    this.errorTarget.hidden = true;
    if (name !== "frame" && this.hasVideoTarget) this.videoTarget.pause();
    if (name === "image" && this.hasSearchTarget) this.searchTarget.focus();
  }

  currentTab() {
    const tab = this.tabTargets.find((t) => t.classList.contains("font-bold"));
    return tab ? tab.dataset.tab : "frame";
  }

  // ── Frame from the video ─────────────────────────────────────────────

  togglePlay() {
    const video = this.videoTarget;
    if (video.paused) video.play(); else video.pause();
  }

  stepBack() { this.step(-1); }
  stepForward() { this.step(1); }

  step(direction) {
    const video = this.videoTarget;
    video.pause();
    const fps = parseFloat(this.panelTarget.dataset.fps) || 30;
    video.currentTime = Math.max(0, Math.min(this.duration(), video.currentTime + direction / fps));
  }

  seek() {
    this.videoTarget.currentTime = parseFloat(this.scrubTarget.value) || 0;
  }

  jump(event) {
    this.videoTarget.pause();
    this.videoTarget.currentTime = parseFloat(event.currentTarget.dataset.at) || 0;
  }

  // The player starts on the poster's own frame (when it came from one),
  // so the window opens showing what the poster is now.
  ready() {
    const start = parseFloat(this.panelTarget.dataset.start);
    if (start > 0 && this.videoTarget.currentTime === 0) this.videoTarget.currentTime = start;
    this.tick();
  }

  // Keep the readout, the scrub bar, PLAY/PAUSE and the JUMP TO outline in
  // step with the video.
  tick() {
    if (!this.hasVideoTarget) return;
    const at = this.videoTarget.currentTime || 0;
    this.timeTarget.textContent = this.formatTime(at);
    if (document.activeElement !== this.scrubTarget) this.scrubTarget.value = at;
    // COPY: play button
    this.playTarget.textContent = this.videoTarget.paused ? "▶ PLAY" : "❚❚ PAUSE";
    const nearest = this.jumpTargets.reduce((best, el) => {
      const d = Math.abs(parseFloat(el.dataset.at) - at);
      return !best || d < best.d ? { el, d } : best;
    }, null);
    const span = this.duration() / Math.max(this.jumpTargets.length, 1);
    this.jumpTargets.forEach((el) => el.classList.toggle("is-current", !!nearest && el === nearest.el && nearest.d <= span / 2));
  }

  duration() {
    const fromVideo = this.hasVideoTarget ? this.videoTarget.duration : NaN;
    return Number.isFinite(fromVideo) && fromVideo > 0 ? fromVideo : parseFloat(this.panelTarget.dataset.duration) || 0;
  }

  useFrame() {
    this.videoTarget.pause();
    this.save({ at: this.videoTarget.currentTime.toFixed(3) }, this.useFrameTarget);
  }

  // ── Image from media ─────────────────────────────────────────────────

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase();
    this.imageTargets.forEach((el) => { el.hidden = query !== "" && !el.dataset.name.includes(query); });
  }

  pickImage(event) {
    const picked = event.currentTarget;
    this.imageTargets.forEach((el) => el.classList.toggle("is-picked", el === picked));
    this.picked = picked.dataset.path;
    this.useImageTarget.disabled = false;
    const name = this.picked.split("/").pop();
    // COPY: picked image note
    this.pickedNoteTarget.textContent = `${name} is copied in as the poster.`;
  }

  useImage() {
    if (this.picked) this.save({ image: this.picked }, this.useImageTarget);
  }

  // ── Saving ───────────────────────────────────────────────────────────

  async save(params, button) {
    const label = button.textContent;
    button.disabled = true;
    // COPY: saving state
    button.textContent = "SAVING…";
    this.errorTarget.hidden = true;
    try {
      const response = await fetch(this.panelTarget.dataset.posterUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify(params),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
      this.saved(data);
    } catch (error) {
      // COPY: save failed
      this.errorTarget.textContent = `Couldn't save the poster: ${error.message}`;
      this.errorTarget.hidden = false;
    } finally {
      button.textContent = label;
      button.disabled = false;
    }
  }

  saved(data) {
    const id = this.panelTarget.dataset.id;
    document.querySelectorAll(`img[data-video-poster="${id}"]`).forEach((img) => {
      img.src = data.poster;
      img.hidden = false;
    });
    this.captionTarget.textContent = data.caption;
    // COPY: close button after a save
    this.closeButtonTarget.textContent = "CLOSE";
  }

  formatTime(seconds) {
    const total = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = String(total % 60).padStart(2, "0");
    return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
  }
}

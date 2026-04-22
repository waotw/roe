import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "audio",
    "video",
    "playButton",
    "progressBar",
    "progressFill",
    "progressHandle",
    "currentTime",
    "duration",
    "speedButton",
    "chapterList",
    "chapterItem",
    "nowPlaying",
    "artwork",
    "title",
  ];

  static values = {
    src: String,
    type: String, // "audio" or "video"
    speed: { type: Number, default: 1 },
    skipSeconds: { type: Number, default: 15 },
  };

  // Available playback speeds
  SPEEDS = [0.75, 1, 1.25, 1.5, 2];

  connect() {
    this.mediaEl = this.hasAudioTarget
      ? this.audioTarget
      : this.hasVideoTarget
        ? this.videoTarget
        : null;
    if (!this.mediaEl) return;

    this._boundTimeUpdate = this.onTimeUpdate.bind(this);
    this._boundDurationChange = this.onDurationChange.bind(this);
    this._boundEnded = this.onEnded.bind(this);
    this._boundPlay = this.onPlay.bind(this);
    this._boundPause = this.onPause.bind(this);

    this.mediaEl.addEventListener("timeupdate", this._boundTimeUpdate);
    this.mediaEl.addEventListener("durationchange", this._boundDurationChange);
    this.mediaEl.addEventListener("ended", this._boundEnded);
    this.mediaEl.addEventListener("play", this._boundPlay);
    this.mediaEl.addEventListener("pause", this._boundPause);

    // Set initial speed
    this.mediaEl.playbackRate = this.speedValue;
    this.updateSpeedButton();

    // Keyboard shortcuts
    this._boundKeydown = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this._boundKeydown);

    // Detect chapters
    this.chapters = this.parseChapters();
    if (this.chapters.length > 0 && this.hasChapterListTarget) {
      this.renderChapters();
    }
  }

  disconnect() {
    if (!this.mediaEl) return;

    this.mediaEl.removeEventListener("timeupdate", this._boundTimeUpdate);
    this.mediaEl.removeEventListener(
      "durationchange",
      this._boundDurationChange,
    );
    this.mediaEl.removeEventListener("ended", this._boundEnded);
    this.mediaEl.removeEventListener("play", this._boundPlay);
    this.mediaEl.removeEventListener("pause", this._boundPause);
    document.removeEventListener("keydown", this._boundKeydown);
  }

  // ========== PLAYBACK CONTROLS ==========

  togglePlay() {
    if (!this.mediaEl) return;
    if (this.mediaEl.paused) {
      this.mediaEl.play();
    } else {
      this.mediaEl.pause();
    }
  }

  skipBack() {
    if (!this.mediaEl) return;
    this.mediaEl.currentTime = Math.max(
      0,
      this.mediaEl.currentTime - this.skipSecondsValue,
    );
  }

  skipForward() {
    if (!this.mediaEl) return;
    const duration = this.mediaEl.duration;
    const currentTime = this.mediaEl.currentTime;
    if (!isFinite(duration) || isNaN(duration)) {
      this.mediaEl.currentTime = currentTime + this.skipSecondsValue;
    } else {
      this.mediaEl.currentTime = Math.min(
        duration,
        currentTime + this.skipSecondsValue,
      );
    }
  }

  cycleSpeed() {
    const current = this.SPEEDS.indexOf(this.speedValue);
    const next = (current + 1) % this.SPEEDS.length;
    this.speedValue = this.SPEEDS[next];
    this.mediaEl.playbackRate = this.speedValue;
    this.updateSpeedButton();
  }

  // ========== PROGRESS BAR ==========

  seek(event) {
    if (!this.mediaEl || !this.mediaEl.duration) return;

    const bar = this.progressBarTarget;
    const rect = bar.getBoundingClientRect();
    const x = (event.clientX ?? event.touches?.[0]?.clientX ?? 0) - rect.left;
    const ratio = Math.max(0, Math.min(1, x / rect.width));
    this.mediaEl.currentTime = ratio * this.mediaEl.duration;
  }

  startScrub(event) {
    event.preventDefault();
    event.stopPropagation();
    this._scrubbing = true;
    this.seek(event);
    this._boundScrubMove = this.scrubMove.bind(this);
    this._boundScrubEnd = this.scrubEnd.bind(this);
    window.addEventListener("mousemove", this._boundScrubMove);
    window.addEventListener("touchmove", this._boundScrubMove);
    window.addEventListener("mouseup", this._boundScrubEnd);
    window.addEventListener("touchend", this._boundScrubEnd);
  }

  scrubMove(event) {
    if (!this._scrubbing) return;
    this.seek(event);
  }

  scrubEnd() {
    this._scrubbing = false;
    window.removeEventListener("mousemove", this._boundScrubMove);
    window.removeEventListener("touchmove", this._boundScrubMove);
    window.removeEventListener("mouseup", this._boundScrubEnd);
    window.removeEventListener("touchend", this._boundScrubEnd);
  }

  // ========== EXTERNAL CONTROL (playlist) ==========

  // Called by playlist to load a new track without full page reload
  loadTrack({ src, title, artwork, duration }) {
    if (!this.mediaEl) return;

    const wasPlaying = !this.mediaEl.paused;
    this.mediaEl.src = src;
    this.mediaEl.load();

    if (this.hasTitleTarget && title) {
      this.titleTarget.textContent = title;
    }

    if (this.hasArtworkTarget && artwork) {
      this.artworkTarget.src = artwork;
      this.artworkTarget.classList.remove("hidden");
    }

    if (wasPlaying) {
      this.mediaEl.play();
    }

    // Update progress immediately
    this.updateProgress(0, 0);
  }

  // ========== MEDIA EVENTS ==========

  onPlay() {
    if (this.hasPlayButtonTarget) {
      this.playButtonTarget.dataset.playing = "true";
      this.playButtonTarget.setAttribute("aria-label", "Pause");
    }
    this.element.classList.add("is-playing");
    this.element.classList.remove("is-paused");
  }

  onPause() {
    if (this.hasPlayButtonTarget) {
      this.playButtonTarget.dataset.playing = "false";
      this.playButtonTarget.setAttribute("aria-label", "Play");
    }
    this.element.classList.remove("is-playing");
    this.element.classList.add("is-paused");
  }

  onEnded() {
    this.element.classList.remove("is-playing");
    this.element.classList.add("is-ended");
    // Dispatch event so playlist can advance to next track
    this.element.dispatchEvent(
      new CustomEvent("audio-player:ended", { bubbles: true }),
    );
  }

  onTimeUpdate() {
    if (!this.mediaEl || this._scrubbing) return;
    const current = this.mediaEl.currentTime;
    const total = this.mediaEl.duration || 0;
    this.updateProgress(current, total);
    this.updateChapterHighlight(current);
  }

  onDurationChange() {
    if (!this.mediaEl) return;
    const total = this.mediaEl.duration || 0;
    if (this.hasDurationTarget) {
      this.durationTarget.textContent = this.formatTime(total);
    }
  }

  // ========== UI UPDATES ==========

  updateProgress(current, total) {
    const ratio = total > 0 ? current / total : 0;

    if (this.hasProgressFillTarget) {
      this.progressFillTarget.style.width = `${ratio * 100}%`;
    }

    if (this.hasProgressHandleTarget) {
      this.progressHandleTarget.style.left = `${ratio * 100}%`;
    }

    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = this.formatTime(current);
    }
  }

  updateSpeedButton() {
    if (this.hasSpeedButtonTarget) {
      this.speedButtonTarget.textContent = `${this.speedValue}×`;
      this.speedButtonTarget.setAttribute(
        "aria-label",
        `Playback speed: ${this.speedValue}x`,
      );
    }
  }

  // ========== CHAPTERS ==========

  parseChapters() {
    // Chapters are stored as JSON in a data attribute on the element
    // data-audio-player-chapters='[{"time":0,"title":"Intro"},{"time":300,"title":"Chapter 1"}]'
    try {
      const raw = this.element.dataset.audioPlayerChapters;
      if (!raw) return [];
      return JSON.parse(raw);
    } catch {
      return [];
    }
  }

  renderChapters() {
    if (!this.hasChapterListTarget) return;

    this.chapterListTarget.innerHTML = this.chapters
      .map(
        (chapter, i) => `
      <li class="audio-player__chapter"
          data-audio-player-target="chapterItem"
          data-time="${chapter.time}"
          data-action="click->audio-player#seekToChapter"
          data-index="${i}">
        <span class="audio-player__chapter-time">${this.formatTime(chapter.time)}</span>
        <span class="audio-player__chapter-title">${chapter.title}</span>
      </li>
    `,
      )
      .join("");
  }

  seekToChapter(event) {
    const time = parseFloat(event.currentTarget.dataset.time);
    if (!isNaN(time) && this.mediaEl) {
      this.mediaEl.currentTime = time;
      if (this.mediaEl.paused) this.mediaEl.play();
    }
  }

  updateChapterHighlight(currentTime) {
    if (this.chapters.length === 0) return;

    let activeIndex = 0;
    for (let i = 0; i < this.chapters.length; i++) {
      if (currentTime >= this.chapters[i].time) {
        activeIndex = i;
      }
    }

    if (this.hasChapterItemTarget) {
      this.chapterItemTargets.forEach((el, i) => {
        el.classList.toggle("is-active", i === activeIndex);
      });
    }

    if (this.hasNowPlayingTarget && this.chapters[activeIndex]) {
      this.nowPlayingTarget.textContent = this.chapters[activeIndex].title;
    }
  }

  // ========== KEYBOARD SHORTCUTS ==========

  handleKeydown(event) {
    // Only handle shortcuts when the player is focused or hovered
    if (
      !this.element.matches(":hover") &&
      !this.element.contains(document.activeElement)
    )
      return;

    // Don't steal keys from inputs
    if (event.target.tagName === "INPUT" || event.target.tagName === "TEXTAREA")
      return;

    switch (event.key) {
      case " ":
      case "k":
        event.preventDefault();
        this.togglePlay();
        break;
      case "ArrowLeft":
      case "j":
        event.preventDefault();
        this.skipBack();
        break;
      case "ArrowRight":
      case "l":
        event.preventDefault();
        this.skipForward();
        break;
    }
  }

  // ========== HELPERS ==========

  formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return "0:00";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) {
      return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
    }
    return `${m}:${String(s).padStart(2, "0")}`;
  }
}

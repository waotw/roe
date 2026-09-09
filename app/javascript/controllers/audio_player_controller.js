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
    upgradeUrl: String,
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
    this._boundError = this.onMediaError.bind(this);
    this._boundPlay = this.onPlay.bind(this);
    this._boundPause = this.onPause.bind(this);

    this.mediaEl.addEventListener("timeupdate", this._boundTimeUpdate);
    this.mediaEl.addEventListener("durationchange", this._boundDurationChange);
    this.mediaEl.addEventListener("ended", this._boundEnded);
    this.mediaEl.addEventListener("error", this._boundError, true);
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

    // Adopt a `playlist` on the page as this transport's queue.
    this.setupPlaylist();
  }

  // Wire this player to a `playlist` collection elsewhere on the page: selecting
  // a row loads it here, playback auto-advances through the list, and the
  // now-playing title/artwork/[info] follow the active track. One player + one
  // playlist per page for now.
  setupPlaylist() {
    this.tracks = [];
    this.currentIndex = -1;
    this.fallbackCover = this.element.getAttribute("data-cover") || "";
    this.infoLink = this.element.querySelector("[data-player-info]");

    const playlist = document.querySelector("[data-playlist]");
    if (!playlist) {
      // Single-source player: the [info] link would just point at the current
      // page, so hide it.
      if (this.infoLink) this.infoLink.hidden = true;
      return;
    }

    this.tracks = Array.prototype.slice.call(
      playlist.querySelectorAll(".player-track"),
    );
    playlist.classList.add("is-enhanced");

    this.tracks.forEach((row, i) => {
      const rowAudio = row.querySelector(".player-track-audio");
      if (rowAudio) rowAudio.hidden = true; // the transport drives playback now

      const select = row.querySelector("[data-player-select]");
      if (select) {
        select.addEventListener("click", (e) => {
          if (e.target.closest && e.target.closest("a")) return; // let [info] navigate
          this.selectTrack(i, true);
        });
      }
    });

    // No source of its own → adopt the first track (paused).
    const hasOwnSource = !!(
      this.mediaEl.currentSrc || this.mediaEl.querySelector("source[src]")
    );
    if (!hasOwnSource && this.tracks.length) this.selectTrack(0, false);
  }

  trackSrc(row) {
    const a = row.querySelector(".player-track-audio");
    const source = a && a.querySelector("source[src]");
    return (
      (a && a.getAttribute("src")) ||
      (source && source.getAttribute("src")) ||
      row.getAttribute("data-audio") ||
      ""
    );
  }

  selectTrack(index, autoplay) {
    if (index < 0 || index >= this.tracks.length) return;
    const row = this.tracks[index];
    const src = this.trackSrc(row);
    if (!src) return;

    this.currentIndex = index;
    this.element.classList.remove("is-ended");
    this.clearPaywall();
    // Server-side marking only says the track IS paid, not whether THIS viewer
    // can play it — a paid member can. So the notice waits for playback to
    // actually fail rather than pre-judging.
    this.currentTrackPaid = row.getAttribute("data-paid") === "true";
    this.mediaEl.src = src;
    this.mediaEl.load();

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = row.getAttribute("data-title") || "";
    }
    if (this.hasArtworkTarget) {
      const image = row.getAttribute("data-image") || this.fallbackCover;
      if (image) {
        this.artworkTarget.src = image;
        this.artworkTarget.hidden = false;
      } else {
        this.artworkTarget.removeAttribute("src");
        this.artworkTarget.hidden = true;
      }
    }
    if (this.infoLink) {
      const url = row.getAttribute("data-url");
      if (url) {
        this.infoLink.setAttribute("href", url);
        this.infoLink.hidden = false;
      }
    }

    this.tracks.forEach((t, j) =>
      t.classList.toggle("is-playing", j === index),
    );

    if (autoplay) this.mediaEl.play();
  }

  disconnect() {
    if (!this.mediaEl) return;

    this.mediaEl.removeEventListener("timeupdate", this._boundTimeUpdate);
    this.mediaEl.removeEventListener(
      "durationchange",
      this._boundDurationChange,
    );
    this.mediaEl.removeEventListener("error", this._boundError);
    this.mediaEl.removeEventListener("ended", this._boundEnded);
    this.mediaEl.removeEventListener("play", this._boundPlay);
    this.mediaEl.removeEventListener("pause", this._boundPause);
    document.removeEventListener("keydown", this._boundKeydown);
  }

  // ========== PAYWALL ==========

  // The audio 403s for anyone not entitled to it, which on its own just looks
  // like a broken player. An <audio> element can't see the status code, so a
  // failure on a track the server marked paid is treated as the paywall.
  onMediaError() {
    if (!this.currentTrackPaid) return;
    this.showPaywall();
  }

  showPaywall() {
    this.element.classList.add("is-paywalled");

    let notice = this.element.querySelector("[data-player-paywall]");
    if (!notice) {
      notice = document.createElement("p");
      notice.dataset.playerPaywall = "";
      notice.className = "player-paywall";
      const body = this.element.querySelector(".player-body") || this.element;
      body.insertAdjacentElement("afterend", notice);
    }

    notice.innerHTML = this.paywallMessage;
  }

  clearPaywall() {
    this.element.classList.remove("is-paywalled");
    this.element.querySelector("[data-player-paywall]")?.remove();
  }

  // upgradeUrlValue is set by the renderer when the site has a members
  // upgrade page; without one, say what's happening and stop there rather
  // than linking somewhere that doesn't exist.
  get paywallMessage() {
    const label = "This track is for paid members.";
    if (!this.hasUpgradeUrlValue || !this.upgradeUrlValue) return label;

    return `${label} <a href="${this.upgradeUrlValue}">Upgrade to listen</a>.`;
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

  toggleFullscreen() {
    const container = this.element;

    if (!document.fullscreenElement) {
      container
        .requestFullscreen?.()
        .then(() => {
          container.classList.add("is-fullscreen");
        })
        .catch((err) => {
          console.warn("Fullscreen error:", err);
        });
    } else {
      document.exitFullscreen?.().then(() => {
        container.classList.remove("is-fullscreen");
      });
    }
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

    // Auto-advance through an adopted playlist.
    if (
      this.tracks &&
      this.tracks.length &&
      this.currentIndex >= 0 &&
      this.currentIndex + 1 < this.tracks.length
    ) {
      this.selectTrack(this.currentIndex + 1, true);
    }
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
      <li class="chapter"
          data-audio-player-target="chapterItem"
          data-time="${chapter.time}"
          data-action="click->audio-player#seekToChapter"
          data-index="${i}">
        <span class="chapter-time">${this.formatTime(chapter.time)}</span>
        <span class="chapter-title">${chapter.title}</span>
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

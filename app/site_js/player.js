/* ============== ROE SCRIPT ================
   Roe Script: player
   Version: 1.0
   Fingerprint: eeb47f48
   Bundled with: Roe v0.4.0

   This file was installed from Roe. Leave this comment in place
   and Admin → Updates will tell you when a newer version ships.
   Edit anything below it freely — Roe can tell, and will never
   overwrite your changes without asking.
   ========================================== */

// Roe's audio and video players — progressive only.
//
// Every player works without this file. Each one is rendered with the
// browser's own controls showing (<audio controls>, <video controls>) and
// Roe's controls hidden, so a page plays even when this script doesn't load:
// a static host, a blocked script, an old browser. This file then swaps them:
// it hides the browser's controls, shows Roe's, and wires them up — play,
// the progress bar, times, speed, skip, chapters, fullscreen, and a
// `playlist` on the page as the player's queue.
//
// The markup it reads (Roe renders it; a theme's CSS styles it):
//   [data-player="audio" | "video"]   one player
//     data-player-skip="15"           seconds for skip back / forward
//     data-player-chapters='[{"time":0,"title":"Intro"}]'
//     data-player-upgrade-url="/join" where a paid track sends people
//     data-cover="/img.jpg"           artwork when a track has none
//   [data-player-part="…"] inside it: media, play, progress, fill, handle,
//     current, duration, speed, back, forward, fullscreen, now, title, artwork
//   [data-player-ui]                  hidden until this script shows it
//   [data-player-chapter][data-time]  a chapter row; clicking seeks there
//   [data-player-info]                the [info] link, shown for a playlist
//   [data-playlist] .player-track     a `playlist` collection's rows
(function () {
  "use strict";

  var SPEEDS = [0.75, 1, 1.25, 1.5, 2];
  var players = [];

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0 || !isFinite(seconds)) return "0:00";
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = Math.floor(seconds % 60);
    var ss = (s < 10 ? "0" : "") + s;
    if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss;
    return m + ":" + ss;
  }

  function Player(root) {
    this.root = root;
    this.media = this.part("media");
    this.skip = parseFloat(root.getAttribute("data-player-skip")) || 15;
    this.speed = 1;
    this.tracks = [];
    this.currentIndex = -1;
    this.currentTrackPaid = false;
    this.scrubbing = false;
  }

  Player.prototype.part = function (name) {
    return this.root.querySelector('[data-player-part="' + name + '"]');
  };

  Player.prototype.parts = function (name) {
    return Array.prototype.slice.call(
      this.root.querySelectorAll('[data-player-part="' + name + '"]'),
    );
  };

  Player.prototype.enhance = function () {
    var self = this;
    var media = this.media;
    var root = this.root;

    // The swap. Set, never toggled, so running again on a page Turbo kept
    // (markup already swapped, listeners gone) lands in the same state.
    Array.prototype.slice
      .call(root.querySelectorAll("[data-player-ui]"))
      .forEach(function (el) {
        el.hidden = false;
      });
    media.controls = false;
    if (media.tagName === "AUDIO") media.hidden = true;
    root.classList.add("is-enhanced");

    media.addEventListener("timeupdate", function () {
      self.onTimeUpdate();
    });
    media.addEventListener("durationchange", function () {
      self.setText("duration", formatTime(media.duration || 0));
    });
    media.addEventListener("loadedmetadata", function () {
      self.setText("duration", formatTime(media.duration || 0));
    });
    media.addEventListener("play", function () {
      self.onPlay();
    });
    media.addEventListener("pause", function () {
      self.onPause();
    });
    media.addEventListener("ended", function () {
      self.onEnded();
    });
    media.addEventListener(
      "error",
      function () {
        if (self.currentTrackPaid) self.showPaywall();
      },
      true,
    );
    if (media.tagName === "VIDEO") {
      media.addEventListener("click", function () {
        self.togglePlay();
      });
    }

    this.on("play", "click", function () {
      self.togglePlay();
    });
    this.on("back", "click", function () {
      self.skipBy(-self.skip);
    });
    this.on("forward", "click", function () {
      self.skipBy(self.skip);
    });
    this.on("speed", "click", function () {
      self.cycleSpeed();
    });
    this.on("fullscreen", "click", function () {
      self.toggleFullscreen();
    });

    var bar = this.part("progress");
    if (bar) {
      var start = function (e) {
        self.startScrub(e);
      };
      bar.addEventListener("mousedown", start);
      bar.addEventListener("touchstart", start, { passive: false });
      bar.addEventListener("keydown", function (e) {
        if (e.key === "ArrowLeft") {
          e.preventDefault();
          self.skipBy(-5);
        } else if (e.key === "ArrowRight") {
          e.preventDefault();
          self.skipBy(5);
        }
      });
    }

    media.playbackRate = this.speed;
    this.updateSpeed();
    if (media.readyState > 0) this.setText("duration", formatTime(media.duration || 0));

    this.setupChapters();
    this.setupPlaylist();
  };

  Player.prototype.on = function (name, event, fn) {
    this.parts(name).forEach(function (el) {
      el.addEventListener(event, function (e) {
        e.preventDefault();
        fn(e);
      });
    });
  };

  Player.prototype.setText = function (name, text) {
    this.parts(name).forEach(function (el) {
      el.textContent = text;
    });
  };

  // ── playback ─────────────────────────────────────────────────────────

  Player.prototype.togglePlay = function () {
    if (this.media.paused) {
      var p = this.media.play();
      if (p && p.catch) p.catch(function () {});
    } else {
      this.media.pause();
    }
  };

  Player.prototype.skipBy = function (seconds) {
    var media = this.media;
    var t = media.currentTime + seconds;
    if (isFinite(media.duration)) t = Math.min(media.duration, t);
    media.currentTime = Math.max(0, t);
  };

  Player.prototype.cycleSpeed = function () {
    var i = SPEEDS.indexOf(this.speed);
    this.speed = SPEEDS[(i + 1) % SPEEDS.length];
    this.media.playbackRate = this.speed;
    this.updateSpeed();
  };

  Player.prototype.updateSpeed = function () {
    var speed = this.speed;
    this.parts("speed").forEach(function (el) {
      el.textContent = speed + "×";
      el.setAttribute("aria-label", "Playback speed: " + speed + "x");
    });
  };

  Player.prototype.toggleFullscreen = function () {
    var root = this.root;
    if (!document.fullscreenElement) {
      if (!root.requestFullscreen) return;
      root
        .requestFullscreen()
        .then(function () {
          root.classList.add("is-fullscreen");
        })
        .catch(function () {});
    } else if (document.exitFullscreen) {
      document.exitFullscreen().then(function () {
        root.classList.remove("is-fullscreen");
      });
    }
  };

  // ── progress bar ─────────────────────────────────────────────────────

  Player.prototype.seek = function (e) {
    var media = this.media;
    var bar = this.part("progress");
    if (!bar || !media.duration || !isFinite(media.duration)) return;
    var rect = bar.getBoundingClientRect();
    var touch = e.touches && e.touches[0];
    var x = (touch ? touch.clientX : e.clientX) - rect.left;
    var ratio = Math.max(0, Math.min(1, x / rect.width));
    media.currentTime = ratio * media.duration;
    this.updateProgress(media.currentTime, media.duration);
  };

  Player.prototype.startScrub = function (e) {
    var self = this;
    e.preventDefault();
    e.stopPropagation();
    this.scrubbing = true;
    this.seek(e);
    function move(ev) {
      if (self.scrubbing) self.seek(ev);
    }
    function end() {
      self.scrubbing = false;
      window.removeEventListener("mousemove", move);
      window.removeEventListener("touchmove", move);
      window.removeEventListener("mouseup", end);
      window.removeEventListener("touchend", end);
    }
    window.addEventListener("mousemove", move);
    window.addEventListener("touchmove", move);
    window.addEventListener("mouseup", end);
    window.addEventListener("touchend", end);
  };

  Player.prototype.updateProgress = function (current, total) {
    var pct = (total > 0 ? current / total : 0) * 100 + "%";
    this.parts("fill").forEach(function (el) {
      el.style.width = pct;
    });
    this.parts("handle").forEach(function (el) {
      el.style.left = pct;
    });
    this.setText("current", formatTime(current));
    var bar = this.part("progress");
    if (bar) bar.setAttribute("aria-valuetext", formatTime(current));
  };

  // ── media events ─────────────────────────────────────────────────────

  Player.prototype.onTimeUpdate = function () {
    if (this.scrubbing) return;
    var current = this.media.currentTime;
    this.updateProgress(current, this.media.duration || 0);
    this.highlightChapter(current);
  };

  Player.prototype.onPlay = function () {
    this.parts("play").forEach(function (el) {
      el.setAttribute("data-playing", "true");
      el.setAttribute("aria-label", "Pause");
    });
    this.root.classList.add("is-playing");
    this.root.classList.remove("is-paused", "is-ended");
  };

  Player.prototype.onPause = function () {
    this.parts("play").forEach(function (el) {
      el.setAttribute("data-playing", "false");
      el.setAttribute("aria-label", "Play");
    });
    this.root.classList.remove("is-playing");
    this.root.classList.add("is-paused");
  };

  Player.prototype.onEnded = function () {
    this.root.classList.remove("is-playing");
    this.root.classList.add("is-ended");
    this.root.dispatchEvent(new CustomEvent("player:ended", { bubbles: true }));
    if (this.tracks.length && this.currentIndex >= 0 && this.currentIndex + 1 < this.tracks.length) {
      this.selectTrack(this.currentIndex + 1, true);
    }
  };

  // ── chapters ─────────────────────────────────────────────────────────
  //
  // Roe renders the chapter list itself, so it reads as a list of times
  // without this file. Here each row becomes a link into the episode.

  Player.prototype.setupChapters = function () {
    var self = this;
    this.chapterRows = Array.prototype.slice.call(
      this.root.querySelectorAll("[data-player-chapter]"),
    );
    this.chapters = this.chapterRows.map(function (row) {
      return parseFloat(row.getAttribute("data-time")) || 0;
    });
    this.chapterRows.forEach(function (row, i) {
      row.setAttribute("tabindex", "0");
      row.setAttribute("role", "button");
      var go = function () {
        self.media.currentTime = self.chapters[i];
        if (self.media.paused) self.togglePlay();
      };
      row.addEventListener("click", go);
      row.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          go();
        }
      });
    });
  };

  Player.prototype.highlightChapter = function (current) {
    if (!this.chapters.length) return;
    var active = 0;
    for (var i = 0; i < this.chapters.length; i++) {
      if (current >= this.chapters[i]) active = i;
    }
    if (active === this.activeChapter) return;
    this.activeChapter = active;
    this.chapterRows.forEach(function (row, j) {
      row.classList.toggle("is-active", j === active);
    });
    var title = this.chapterRows[active].querySelector(".chapter-title");
    if (title) this.setText("now", title.textContent);
  };

  // ── playlist ─────────────────────────────────────────────────────────
  //
  // A `playlist` collection elsewhere on the page becomes this player's
  // queue: choosing a row loads it here, and playback runs on down the list.
  // One player and one playlist per page for now. Without this file every
  // row plays on its own, in its own browser controls.

  Player.prototype.setupPlaylist = function () {
    var self = this;
    var info = this.root.querySelector("[data-player-info]");
    var playlist = document.querySelector("[data-playlist]");
    if (!playlist || this.root.contains(playlist)) return;
    // The first player on the page owns the playlist.
    if (playlist._playerOwner && playlist._playerOwner !== this && document.contains(playlist._playerOwner.root)) return;
    playlist._playerOwner = this;

    this.info = info;
    this.fallbackCover = this.root.getAttribute("data-cover") || "";
    this.tracks = Array.prototype.slice.call(playlist.querySelectorAll(".player-track"));
    playlist.classList.add("is-enhanced");

    this.tracks.forEach(function (row, i) {
      var rowAudio = row.querySelector(".player-track-audio");
      if (rowAudio) rowAudio.hidden = true;
      var select = row.querySelector("[data-player-select]");
      if (!select) return;
      select.addEventListener("click", function (e) {
        if (e.target.closest && e.target.closest("a")) return; // let a link go
        self.selectTrack(i, true);
      });
    });

    var hasOwn = !!(this.media.getAttribute("src") || this.media.querySelector("source[src]"));
    if (!hasOwn && this.tracks.length) this.selectTrack(0, false);
  };

  Player.prototype.trackSrc = function (row) {
    var a = row.querySelector(".player-track-audio");
    var source = a && a.querySelector("source[src]");
    return (a && a.getAttribute("src")) || (source && source.getAttribute("src")) || row.getAttribute("data-audio") || "";
  };

  Player.prototype.selectTrack = function (index, autoplay) {
    var row = this.tracks[index];
    var src = row && this.trackSrc(row);
    if (!src) return;

    this.currentIndex = index;
    this.root.classList.remove("is-ended");
    this.clearPaywall();
    // Marked paid says the track IS paid, not whether this listener can
    // play it — a paid member can. So the notice waits for playback to fail.
    this.currentTrackPaid = row.getAttribute("data-paid") === "true";
    this.media.src = src;
    this.media.load();

    this.setText("title", row.getAttribute("data-title") || "");
    var image = row.getAttribute("data-image") || this.fallbackCover;
    this.parts("artwork").forEach(function (img) {
      if (image) {
        img.src = image;
        img.hidden = false;
      } else {
        img.removeAttribute("src");
        img.hidden = true;
      }
    });
    var url = row.getAttribute("data-url");
    if (this.info && url) {
      this.info.setAttribute("href", url);
      this.info.hidden = false;
    }

    this.tracks.forEach(function (t, j) {
      t.classList.toggle("is-playing", j === index);
    });

    if (autoplay) {
      var p = this.media.play();
      if (p && p.catch) p.catch(function () {});
    }
  };

  // ── paywall ──────────────────────────────────────────────────────────
  //
  // A paid track answers 403 to anyone not entitled to it, which on its own
  // looks like a broken player. An <audio> can't see the status code, so a
  // failure on a track marked paid is taken to be the paywall.

  Player.prototype.showPaywall = function () {
    this.root.classList.add("is-paywalled");
    var notice = this.root.querySelector("[data-player-paywall]");
    if (!notice) {
      notice = document.createElement("p");
      notice.setAttribute("data-player-paywall", "");
      notice.className = "player-paywall";
      var body = this.root.querySelector(".player-body") || this.root;
      body.insertAdjacentElement("afterend", notice);
    }
    notice.textContent = "This track is for paid members. ";
    var url = this.root.getAttribute("data-player-upgrade-url");
    if (url) {
      var a = document.createElement("a");
      a.href = url;
      a.textContent = "Upgrade to listen";
      notice.appendChild(a);
      notice.appendChild(document.createTextNode("."));
    }
  };

  Player.prototype.clearPaywall = function () {
    this.root.classList.remove("is-paywalled");
    var notice = this.root.querySelector("[data-player-paywall]");
    if (notice) notice.remove();
  };

  // ── keyboard ─────────────────────────────────────────────────────────
  //
  // Space/k play and pause, ←/j and →/l skip — for the player under the
  // pointer or holding focus. One listener for the page, not one per player.

  function onKeydown(e) {
    var tag = e.target && e.target.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || (e.target && e.target.isContentEditable)) return;
    var player = null;
    for (var i = 0; i < players.length; i++) {
      var root = players[i].root;
      if (!document.contains(root)) continue;
      if (root.matches(":hover") || root.contains(document.activeElement)) {
        player = players[i];
        break;
      }
    }
    if (!player) return;
    // A focused button or the progress bar handles its own keys.
    if ((e.key === " " || e.key === "Enter") && tag === "BUTTON") return;
    if ((e.key === "ArrowLeft" || e.key === "ArrowRight") && e.target.getAttribute && e.target.getAttribute("data-player-part") === "progress") return;

    switch (e.key) {
      case " ":
      case "k":
        e.preventDefault();
        player.togglePlay();
        break;
      case "ArrowLeft":
      case "j":
        e.preventDefault();
        player.skipBy(-player.skip);
        break;
      case "ArrowRight":
      case "l":
        e.preventDefault();
        player.skipBy(player.skip);
        break;
    }
  }

  // ── start ────────────────────────────────────────────────────────────

  function init() {
    players = players.filter(function (p) {
      return document.contains(p.root);
    });
    Array.prototype.slice.call(document.querySelectorAll("[data-player]")).forEach(function (root) {
      // Once per element. With Turbo, coming back to a page shows the copy
      // it kept — already swapped, but without the listeners behind it —
      // and that copy is wired again from scratch.
      if (root._player) return;
      var player = new Player(root);
      if (!player.media) return;
      root._player = player;
      players.push(player);
      player.enhance();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
  // Turbo page changes on the dynamic site don't fire DOMContentLoaded.
  // Harmless on a static site, where this never fires.
  document.addEventListener("turbo:load", init);
  document.addEventListener("keydown", onKeydown);
})();

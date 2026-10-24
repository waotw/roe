import { Controller } from "@hotwired/stimulus";

// Uploads media from the browse page without leaving it. For each selected
// file it drops an optimistic placeholder card at the top of the grid, POSTs
// the file (one request each), then swaps the placeholder for the real card
// the server renders — or turns it into a clear error state. Sequential on
// purpose: the server's duplicate-filename suffixing isn't concurrency-safe.
export default class extends Controller {
  static targets = ["grid", "empty", "videoProgress"];

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]')?.content;
    // Live-update any card whose variants are still processing on load, so the
    // ⏳ badge isn't stuck until a manual refresh (cap to avoid a poll storm).
    if (this.hasGridTarget) {
      Array.from(
        this.gridTarget.querySelectorAll('[data-variants-pending="true"]'),
      )
        .slice(0, 24)
        .forEach((card) => this.watchVariants(card));
    }
  }

  // Bound to the file input's change event.
  upload(event) {
    const input = event.target;
    const files = Array.from(input.files || []);
    input.value = ""; // let the same file be re-picked later
    if (files.length) this.uploadNext(files, 0);
  }

  async uploadNext(files, i) {
    if (i >= files.length) return;
    const file = files[i];
    const placeholder = this.addPlaceholder(file);

    // A video opens the progress window straight away, showing the upload
    // itself, so a big file never looks like nothing is happening.
    const progress = this.isVideo(file) ? this.videoProgress() : null;
    if (progress) progress.startUpload(file.name);

    try {
      const data = await this.postFile(file, progress ? (f) => progress.uploadProgress(f) : null);
      if (data && data.success) {
        this.resolvePlaceholder(placeholder, data.card_html, data.message);
        if (progress) {
          if (data.video_optimizing) {
            progress.openFor({ id: data.media_id, name: data.filename });
          } else {
            progress.close();
          }
        }
      } else {
        this.errorPlaceholder(placeholder, file.name, data && data.error);
        if (progress) progress.uploadFailed(data && data.error);
      }
    } catch {
      this.errorPlaceholder(
        placeholder,
        file.name,
        "Upload failed — please try again.",
      );
      if (progress) progress.uploadFailed();
    }
    this.uploadNext(files, i + 1);
  }

  isVideo(file) {
    return (
      (file.type || "").startsWith("video/") ||
      /\.(mp4|m4v|mov|webm|mkv|avi|ogv)$/i.test(file.name || "")
    );
  }

  // XMLHttpRequest rather than fetch: fetch can't report how much of the
  // file has gone up, and that's what the progress window shows while a
  // big video uploads. onProgress gets 0..1, or null when it can't tell.
  postFile(file, onProgress) {
    const body = new FormData();
    body.append("files[]", file);
    return new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      xhr.open("POST", "/admin/medium");
      xhr.setRequestHeader("Accept", "application/json");
      xhr.setRequestHeader("X-CSRF-Token", this.token || "");
      if (onProgress) {
        xhr.upload.onprogress = (e) => onProgress(e.lengthComputable ? e.loaded / e.total : null);
      }
      xhr.onload = () => {
        try {
          resolve(JSON.parse(xhr.responseText));
        } catch {
          resolve({ success: false, error: "Upload failed." });
        }
      };
      xhr.onerror = () => resolve({ success: false, error: "Upload failed — please try again." });
      xhr.send(body);
    });
  }

  addPlaceholder(file) {
    if (this.hasEmptyTarget) this.emptyTarget.remove();
    const el = document.createElement("div");
    el.className =
      "border border-gray-300 p-2 flex flex-col items-center justify-center text-center min-h-[13rem]";
    el.innerHTML = `
      <div class="animate-spin h-6 w-6 border-2 border-gray-300 border-t-amber-600 rounded-full mb-2"></div>
      <div class="text-xs text-gray-500 break-all">${this.escape(file.name)}</div>`;
    this.gridTarget.prepend(el);
    return el;
  }

  resolvePlaceholder(placeholder, cardHtml, message) {
    const tmp = document.createElement("div");
    tmp.innerHTML = (cardHtml || "").trim();
    const card = tmp.firstElementChild;
    if (card) {
      placeholder.replaceWith(card);
      this.watchVariants(card);
      // Apply the active tab/search filter to the newly-inserted card.
      this.reapplyFilters();
    } else {
      placeholder.remove();
    }
    if (message) this.toast(message);
  }

  // Re-run the media-filter controller so a card injected or swapped after
  // load (upload result, variant-poll refresh) obeys the active tab, search,
  // and audience filters instead of showing everywhere. media-filter sits on
  // an element INSIDE this one (browse.html.erb: media-upload wraps the
  // header and the grid), so look for it there. Asking for it on
  // this.element found nothing, and every swapped card showed under every
  // tab: a used GIF under Unused, images under Video and Audio.
  reapplyFilters() {
    const app = this.application;
    if (!app) return;
    const host = this.element.matches('[data-controller~="media-filter"]')
      ? this.element
      : this.element.querySelector('[data-controller~="media-filter"]');
    if (!host) return;
    const filter = app.getControllerForElementAndIdentifier(host, "media-filter");
    if (filter && typeof filter.applyFilters === "function") {
      filter.applyFilters();
    }
  }

  // The progress window's controller (video-progress), or null.
  videoProgress() {
    if (!this.hasVideoProgressTarget || !this.application) return null;
    return this.application.getControllerForElementAndIdentifier(
      this.videoProgressTarget,
      "video-progress",
    );
  }

  // A video's web versions take minutes to make, so the progress window
  // shows them (video-progress controller). Closing it is fine: the work
  // carries on and the card keeps polling its own progress.
  openVideoProgress(id, name) {
    const progress = this.videoProgress();
    if (progress) progress.openFor({ id, name });
  }

  // A video finished (or failed) while the page was open: bring in the
  // notice the Media Browser would show on a fresh load, without a
  // refresh. Called by the progress window ("video-progress:finished")
  // and by a card's poll when it sees the video finish — which covers
  // videos uploaded from the editor, too.
  refreshNotices() {
    fetch("/admin/medium/video_notices", { headers: { Accept: "text/html" } })
      .then((r) => (r.ok ? r.text() : null))
      .then((html) => {
        if (html === null) return;
        const current = document.getElementById("video-notices-slot");
        if (current) current.innerHTML = html;
      })
      .catch(() => {});
  }

  // Clicking a video's thumbnail while it's still optimizing reopens the
  // progress window, to check in on it. Reads the state from the card as
  // it is now (the poll keeps swapping it), so a finished video's click
  // does nothing extra.
  openFromCard(event) {
    const thumb = event.currentTarget.querySelector("[data-video-progress-id]");
    if (!thumb || thumb.dataset.videoState !== "optimizing") return;
    this.openVideoProgress(thumb.dataset.videoProgressId, thumb.dataset.videoProgressName);
  }

  // Poll the card endpoint while its variants are processing, swapping the
  // card each time, and stop once the server reports it's no longer
  // pending. Image variants usually finish within a second or two; video
  // takes minutes, so video cards poll slower and for as long as it takes.
  //
  // A request that fails — Roe restarting (roe restart, an update), the
  // computer waking from sleep — is tried again a little later rather than
  // ending the watch. Ending it left the card showing the percentage it had
  // reached until the page was reloaded, while the progress window, which
  // already tried again, carried on.
  watchVariants(card) {
    if (!card || card.dataset.variantsPending !== "true") return;
    const id = card.dataset.mediaId;
    if (!id) return;
    const video = card.dataset.mediaType === "video";
    const interval = video ? 4000 : 1500;
    const maxAttempts = video ? Infinity : 8;

    let attempts = 0;
    const retry = () => {
      if (attempts < maxAttempts && document.contains(this.element)) {
        setTimeout(poll, interval * 2);
      }
    };
    const poll = () => {
      attempts += 1;
      fetch(`/admin/medium/${id}/card`, {
        headers: { Accept: "application/json" },
      })
        .then((r) => (r.ok ? r.json() : null))
        .then((data) => {
          if (!data) return retry();
          const current = this.gridTarget.querySelector(
            `[data-media-id="${id}"]`,
          );
          if (!current) return; // removed/deleted meanwhile
          const tmp = document.createElement("div");
          tmp.innerHTML = (data.card_html || "").trim();
          const fresh = tmp.firstElementChild;
          if (fresh) {
            current.replaceWith(fresh);
            // A freshly-injected card has no display filtering applied, so it
            // would show under every tab (Audio/Video/Unused) regardless of
            // type. Re-run the active filter so the swapped card obeys it.
            this.reapplyFilters();
          }
          if (
            data.pending &&
            attempts < maxAttempts &&
            document.contains(this.element)
          ) {
            setTimeout(poll, interval);
          } else if (video && !data.pending) {
            this.refreshNotices();
          }
        })
        .catch(retry);
    };
    setTimeout(poll, interval);
  }

  errorPlaceholder(placeholder, name, error) {
    placeholder.className =
      "media-upload-error border border-red-300 bg-red-50 p-2 flex flex-col justify-center text-center min-h-[13rem] relative";
    placeholder.innerHTML = `
      <button type="button" data-action="click->media-upload#dismiss"
              class="absolute top-1 right-1 text-red-400 hover:text-red-600 text-base leading-none">&times;</button>
      <div class="text-xs font-semibold text-red-700 break-all mb-1">${this.escape(name)}</div>
      <div class="text-xs text-red-600">${this.escape(error || "Upload failed")}</div>`;
  }

  dismiss(event) {
    event.target.closest(".media-upload-error")?.remove();
  }

  toast(message) {
    const t = document.createElement("div");
    t.className =
      "fixed bottom-4 right-4 z-50 bg-gray-900 text-white text-sm px-3 py-2 rounded shadow-lg max-w-sm";
    t.textContent = message;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 4500);
  }

  escape(s) {
    const d = document.createElement("div");
    d.textContent = s ?? "";
    return d.innerHTML;
  }
}

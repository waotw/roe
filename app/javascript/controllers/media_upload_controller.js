import { Controller } from "@hotwired/stimulus";

// Uploads media from the browse page without leaving it. For each selected
// file it drops an optimistic placeholder card at the top of the grid, POSTs
// the file (one request each), then swaps the placeholder for the real card
// the server renders — or turns it into a clear error state. Sequential on
// purpose: the server's duplicate-filename suffixing isn't concurrency-safe.
export default class extends Controller {
  static targets = ["grid", "empty"];

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]')?.content;
    // Live-update any card whose variants are still processing on load, so the
    // ⏳ badge isn't stuck until a manual refresh (cap to avoid a poll storm).
    if (this.hasGridTarget) {
      Array.from(this.gridTarget.querySelectorAll('[data-variants-pending="true"]'))
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
    try {
      const data = await this.postFile(file);
      if (data && data.success) {
        this.resolvePlaceholder(placeholder, data.card_html, data.message);
      } else {
        this.errorPlaceholder(placeholder, file.name, data && data.error);
      }
    } catch {
      this.errorPlaceholder(placeholder, file.name, "Upload failed — please try again.");
    }
    this.uploadNext(files, i + 1);
  }

  postFile(file) {
    const body = new FormData();
    body.append("files[]", file);
    return fetch("/admin/medium", {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.token || "" },
      body,
    }).then((r) => r.json().catch(() => ({ success: false, error: "Upload failed." })));
  }

  addPlaceholder(file) {
    if (this.hasEmptyTarget) this.emptyTarget.remove();
    const el = document.createElement("div");
    el.className =
      "border border-gray-300 p-2 flex flex-col items-center justify-center text-center min-h-[13rem]";
    el.innerHTML = `
      <div class="animate-spin h-6 w-6 border-2 border-gray-300 border-t-lime-600 rounded-full mb-2"></div>
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
    } else {
      placeholder.remove();
    }
    if (message) this.toast(message);
  }

  // Poll the card endpoint while its image variants are processing, swapping
  // the card each time, and stop once the server reports it's no longer
  // pending (or after a cap). Variants usually finish within a second or two.
  watchVariants(card) {
    if (!card || card.dataset.variantsPending !== "true") return;
    const id = card.dataset.mediaId;
    if (!id) return;

    let attempts = 0;
    const poll = () => {
      attempts += 1;
      fetch(`/admin/medium/${id}/card`, { headers: { Accept: "application/json" } })
        .then((r) => (r.ok ? r.json() : null))
        .then((data) => {
          if (!data) return;
          const current = this.gridTarget.querySelector(`[data-media-id="${id}"]`);
          if (!current) return; // removed/deleted meanwhile
          const tmp = document.createElement("div");
          tmp.innerHTML = (data.card_html || "").trim();
          const fresh = tmp.firstElementChild;
          if (fresh) current.replaceWith(fresh);
          if (data.pending && attempts < 8) setTimeout(poll, 1500);
        })
        .catch(() => {});
    };
    setTimeout(poll, 1500);
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

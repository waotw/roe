import { Controller } from "@hotwired/stimulus";

// Work the media grid does only for cards on screen, so a large library
// loads as fast as a small one:
//
// - "Used in": cards arrive with a placeholder ([data-usages-pending]);
//   once a card scrolls near the screen its link list is fetched, in
//   batches, from MediumController#usages.
// - Previews still being made ([data-variants-pending="true"]): the card is
//   polled — which also queues its preview — only once it's on screen,
//   through media-upload's watchVariants. Each file is watched once per
//   page.
//
// Cards hidden by a tab or search never intersect, so they cost nothing.
// Cards added later (an upload, a poll swapping a card) are picked up by
// the MutationObserver.
export default class extends Controller {
  static values = { usagesUrl: String };

  connect() {
    this.queued = new Set();
    this.watched = new Set();
    this.timer = null;

    this.intersection = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) this.visible(entry.target);
        });
      },
      { rootMargin: "400px 0px" },
    );
    this.observeAll(this.element);

    this.mutation = new MutationObserver((records) => {
      records.forEach((record) =>
        record.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) this.observeAll(node);
        }),
      );
    });
    this.mutation.observe(this.element, { childList: true });
  }

  disconnect() {
    this.intersection?.disconnect();
    this.mutation?.disconnect();
    clearTimeout(this.timer);
  }

  observeAll(root) {
    const cards = root.matches?.("[data-media-id][data-media-filter-target]")
      ? [root]
      : root.querySelectorAll("[data-media-id][data-media-filter-target]");
    cards.forEach((card) => this.intersection.observe(card));
  }

  visible(card) {
    this.intersection.unobserve(card);
    const id = card.dataset.mediaId;

    if (card.querySelector("[data-usages-pending]")) {
      this.queued.add(id);
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.loadUsages(), 80);
    }

    if (card.dataset.variantsPending === "true" && !this.watched.has(id)) {
      this.watched.add(id);
      this.uploadController()?.watchVariants(card);
    }
  }

  async loadUsages() {
    const ids = Array.from(this.queued).slice(0, 100);
    ids.forEach((id) => this.queued.delete(id));
    if (ids.length === 0) return;

    const query = ids.map((id) => `ids[]=${encodeURIComponent(id)}`).join("&");
    try {
      const response = await fetch(`${this.usagesUrlValue}?${query}`, {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) throw new Error(response.status);
      const html = await response.json();
      Object.entries(html).forEach(([id, markup]) => {
        const slot = this.element.querySelector(
          `[data-usages-pending="${CSS.escape(id)}"]`,
        );
        if (slot) slot.outerHTML = markup;
      });
    } catch {
      // Put them back; the next card to scroll in retries them all.
      ids.forEach((id) => this.queued.add(id));
    }

    if (this.queued.size > 0) {
      this.timer = setTimeout(() => this.loadUsages(), 80);
    }
  }

  // media-upload sits on an element around this one, not on it.
  uploadController() {
    const host = this.element.closest('[data-controller~="media-upload"]');
    return host
      ? this.application.getControllerForElementAndIdentifier(
          host,
          "media-upload",
        )
      : null;
  }
}

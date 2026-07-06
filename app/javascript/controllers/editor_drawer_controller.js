import { Controller } from "@hotwired/stimulus";

// Sticky bottom action drawer for the editor. Watches the in-flow primary
// actions row (anchorValue selector) with an IntersectionObserver: while that
// row is scrolled out of view, this drawer slides up from the bottom so Save /
// Preview / (Un)publish + the save-state dot stay reachable; when the row is
// back in view, the drawer tucks away.
//
// The drawer element itself is a `position: fixed` bar and lives inside the
// editor controller, so its buttons' actions/targets resolve there. This
// controller only owns visibility.
export default class extends Controller {
  static values = { anchor: String };

  connect() {
    this.anchorEl = this.anchorValue
      ? document.querySelector(this.anchorValue)
      : null;

    // No anchor or no IntersectionObserver: leave the drawer hidden rather than
    // pinning a permanent bar over the content.
    if (!this.anchorEl || typeof IntersectionObserver === "undefined") return;

    // Keyed per editor page so open/closed survives the save-reload.
    this.stateKey = `roe-drawer-open:${window.location.pathname}`;

    // Restore the last state instantly (no animation) so a save/refresh keeps
    // the drawer exactly as it was — open stays open, closed stays closed.
    this.apply(sessionStorage.getItem(this.stateKey) === "1");

    // Turn the slide on only after this first paint, so the restore above is
    // instant and only later scroll-driven changes animate. Inline style (not a
    // Tailwind class) so it's guaranteed to exist regardless of content
    // scanning — translate-y-full toggles the transform, this animates it.
    requestAnimationFrame(() => {
      this.element.style.transition = "transform 150ms ease-out";
    });

    // Skip the observer's initial snapshot: it fires before the editor restores
    // scroll (which happens in a rAF), so it would briefly report the top-of-
    // page state and fight the restored drawer state. Real scroll changes after
    // that are honoured.
    this.primed = false;
    this.observer = new IntersectionObserver(
      (entries) => {
        if (!this.primed) {
          this.primed = true;
          return;
        }
        for (const entry of entries) this.apply(!entry.isIntersecting);
      },
      { threshold: 0 },
    );
    this.observer.observe(this.anchorEl);
  }

  disconnect() {
    if (this.observer) this.observer.disconnect();
  }

  // open === true → drawer up; false → tucked below. Persisted so a refresh
  // restores the same state.
  apply(open) {
    this.element.classList.toggle("translate-y-full", !open);
    sessionStorage.setItem(this.stateKey, open ? "1" : "0");
  }
}

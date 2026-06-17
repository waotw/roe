import { Controller } from "@hotwired/stimulus";

// Auto-hides a secondary region of a sticky toolbar based on the
// direction of the user's wheel/trackpad input. The primary part of
// the toolbar stays visible at all times. Used by the post/page/
// product/email editor to keep the markdown button bar permanently
// pinned while letting the TOC toggle + panel disappear when the
// user is scrolling down through their content.
//
// WHY WHEEL EVENTS, NOT SCROLL EVENTS — earlier versions of this
// controller read window.scrollY changes to infer scroll direction.
// That broke on short posts: the act of collapsing the TOC shrinks
// the document, which causes the browser to clamp scrollY back
// toward the new max, which fires a `scroll` event that looks
// indistinguishable from a user scrolling up, which re-expands the
// TOC, which makes the document tall again, and so on at ~3 Hz.
// Wheel events carry direction (`event.deltaY`) in the input event
// itself; they're never synthesized by clamping. By switching to
// the wheel signal, the feedback loop is structurally impossible
// regardless of post length, viewport size, or where the user is
// in the document.
//
// Usage:
//   <div data-controller="sticky-toolbar" class="sticky top-0 ...">
//     <div>… always-visible part …</div>
//     <div data-sticky-toolbar-target="collapsible"
//          class="overflow-hidden transition-[max-height] duration-200 ease-out">
//       … collapsible part …
//     </div>
//   </div>
export default class extends Controller {
  static targets = [ "collapsible" ];

  connect() {
    this.handler = this.onWheel.bind(this);
    window.addEventListener("wheel", this.handler, { passive: true });
  }

  disconnect() {
    window.removeEventListener("wheel", this.handler);
  }

  onWheel(event) {
    if (event.deltaY > 0) {
      this.hide();
    } else if (event.deltaY < 0) {
      this.show();
    }
  }

  hide() {
    if (!this.hasCollapsibleTarget) return;
    const el = this.collapsibleTarget;
    if (el.style.maxHeight === "0px") return; // already collapsed

    // Set explicit pixel max-height before collapsing so the
    // transition has a concrete "from" value — transitions from
    // `none` (the cleared state) don't animate.
    el.style.maxHeight = el.scrollHeight + "px";
    // Force a reflow so the browser registers the start value before
    // we change to 0; without this the two style writes collapse
    // into one frame and the animation is skipped.
    void el.offsetHeight;
    el.style.maxHeight = "0px";
  }

  show() {
    if (!this.hasCollapsibleTarget) return;
    const el = this.collapsibleTarget;
    if (el.style.maxHeight !== "0px") return; // already expanded

    // scrollHeight returns full content height even when the element
    // is currently clipped by max-height: 0, so this gives us the
    // correct target height to animate to.
    el.style.maxHeight = el.scrollHeight + "px";

    // After the expansion finishes, clear the inline max-height so
    // the contents can grow freely — important because the TOC panel
    // inside can toggle open/closed and would otherwise be clipped.
    el.addEventListener("transitionend", () => {
      if (el.style.maxHeight !== "0px") el.style.maxHeight = "";
    }, { once: true });
  }
}

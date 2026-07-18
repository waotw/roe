import { Controller } from "@hotwired/stimulus";

// Public-site heading anchors. For every heading with an id, drops a small
// "copy link" control in the left gutter that appears on hover. Clicking it
// copies a canonical URL to that heading to the clipboard. Desktop/hover only —
// CSS hides it where there's no hover or no gutter room (mobile). See the
// heading-anchor styles in layouts/site.html.erb.
export default class extends Controller {
  static targets = ["icon", "copiedIcon"];

  connect() {
    // Scope to the rendered content; fall back to the whole element so a page
    // without a `.content` wrapper still works.
    const scope = this.element.querySelector(".content") || this.element;
    scope
      .querySelectorAll("h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]")
      .forEach((heading) => {
        // Collections render their own heading/title tags (collection
        // heading, item titles, menus). Those aren't authored content
        // sections, so skip any heading inside a collection container.
        if (heading.closest(".collection, .collection-header, .collection-menu")) return;
        this.decorate(heading);
      });
  }

  disconnect() {
    clearTimeout(this.copiedTimer);
  }

  decorate(heading) {
    if (heading.querySelector(".heading-anchor")) return; // idempotent
    heading.classList.add("has-heading-anchor");

    const anchor = document.createElement("a");
    anchor.className = "heading-anchor";
    anchor.href = `#${heading.id}`;
    anchor.title = "Copy link";
    anchor.setAttribute("aria-label", "Copy link to this section");

    this.appendIcon(anchor, this.hasIconTarget && this.iconTarget, "ha-icon-default");
    this.appendIcon(anchor, this.hasCopiedIconTarget && this.copiedIconTarget, "ha-icon-copied");

    anchor.addEventListener("click", (event) => this.copy(event, heading.id, anchor));
    heading.appendChild(anchor);
  }

  // Insert both icons once; CSS toggles which one shows via the `.copied`
  // class on the anchor.
  appendIcon(anchor, template, className) {
    const svg = template && template.content.firstElementChild;
    if (!svg) return;
    const clone = svg.cloneNode(true);
    clone.classList.add("ha-icon", className);
    anchor.appendChild(clone);
  }

  copy(event, id, anchor) {
    event.preventDefault();
    // Swap to the clipboard icon immediately so the feedback is instant on
    // click; write to the clipboard (best-effort) in the background.
    this.flash(anchor);
    history.replaceState(null, "", `#${id}`);

    const url = `${location.origin}${location.pathname}#${id}`;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).catch(() => this.fallbackCopy(url));
    } else {
      this.fallbackCopy(url);
    }
  }

  // Clipboard API needs a secure context (https/localhost); fall back to a
  // hidden textarea + execCommand for plain-http self-hosted sites.
  fallbackCopy(text) {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand("copy");
    } catch (_) {
      /* clipboard unavailable — no-op */
    }
    ta.remove();
  }

  // Instantly show the "copied" icon, then revert after ~1s (no fade).
  flash(anchor) {
    anchor.classList.add("copied");
    clearTimeout(this.copiedTimer);
    this.copiedTimer = setTimeout(() => anchor.classList.remove("copied"), 1000);
  }
}

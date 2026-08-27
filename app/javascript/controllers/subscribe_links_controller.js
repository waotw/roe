import { Controller } from "@hotwired/stimulus";

// Makes subscribe links behave sensibly per device.
//
// Two problems this solves. First, a feed URL is useless as a link on a phone:
// tapping it opens a wall of XML in the browser, and what you actually wanted
// was the URL on your clipboard so you could paste it into a podcast app. On a
// computer, a link is exactly right — every desktop client takes a pasted URL
// and a browser can at least show you the feed.
//
// Second, some app links only work somewhere. Overcast's web page can't
// subscribe you to anything, so on a desktop it's a dead end; Apple Podcasts
// has no Android app, so `podcasts.apple.com` there is a browser page offering
// nothing. Rather than show every link everywhere and let people find the
// broken ones, each is marked with where it belongs.
//
// Markup:
//   <div data-controller="subscribe-links">
//     <a data-platforms="ios">Overcast</a>            ← iOS only
//     <a data-platforms="desktop ios">Apple</a>        ← both, not Android
//     <a data-copy-on-mobile href="/feed.xml">RSS</a>  ← link here, copy there
//   </div>
//
// Unmarked children are left alone, so anything that works everywhere needs
// no annotation.
export default class extends Controller {
  static values = { copiedLabel: { type: String, default: "Copied" } };

  connect() {
    this.platform = this.detectPlatform();
    this.element.dataset.platform = this.platform;

    this.applyPlatformVisibility();
    this.applyMobileCopy();
  }

  // Coarse on purpose: the question is only "which of three sets of links is
  // worth showing", and a wrong guess costs a hidden link rather than a broken
  // page. iPadOS reports itself as a Mac, so the touch check catches it.
  detectPlatform() {
    const ua = navigator.userAgent || "";

    if (/android/i.test(ua)) return "android";
    if (/iPad|iPhone|iPod/.test(ua)) return "ios";
    if (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) return "ios";

    return "desktop";
  }

  get isMobile() {
    return this.platform === "ios" || this.platform === "android";
  }

  // Hidden rather than removed: a link that's wrong here may be right on the
  // same person's phone, and leaving it in the DOM keeps the markup one thing.
  applyPlatformVisibility() {
    this.element.querySelectorAll("[data-platforms]").forEach((el) => {
      const allowed = el.dataset.platforms.split(/\s+/).filter(Boolean);
      el.hidden = !allowed.includes(this.platform);
    });
  }

  applyMobileCopy() {
    if (!this.isMobile) return;

    this.element.querySelectorAll("[data-copy-on-mobile]").forEach((el) => {
      el.dataset.originalLabel = el.textContent.trim();
      el.setAttribute("role", "button");
      el.addEventListener("click", (event) => this.copyInstead(event, el));
    });
  }

  async copyInstead(event, el) {
    // Only take over when we can actually deliver: without a clipboard the
    // link is still better than nothing, so let it through.
    if (!navigator.clipboard) return;

    event.preventDefault();

    try {
      await navigator.clipboard.writeText(this.absoluteUrl(el.getAttribute("href")));
      this.flash(el);
    } catch (e) {
      // Denied or unavailable — fall back to following the link, which is
      // where the browser would have gone anyway.
      window.location.href = el.getAttribute("href");
    }
  }

  // A podcast app needs the whole address, not /feed.xml.
  absoluteUrl(href) {
    return new URL(href, window.location.origin).toString();
  }

  flash(el) {
    el.textContent = this.copiedLabelValue;
    clearTimeout(el.dataset.revertTimer);
    el.dataset.revertTimer = setTimeout(() => {
      el.textContent = el.dataset.originalLabel;
    }, 1500);
  }
}

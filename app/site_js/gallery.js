// Roe gallery enhancements — progressive only.
//
// Galleries work without this file: click-to-zoom is pure CSS (:target),
// and the carousel is CSS scroll-snap (swipe/scroll/snap). This just adds
// prev/next buttons + dots to carousels and Escape/arrow-key handling for
// the zoom lightbox. It's a theme file — edit or replace it freely.
(function () {
  "use strict";

  function el(tag, className, attrs) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (attrs)
      Object.keys(attrs).forEach(function (k) {
        node.setAttribute(k, attrs[k]);
      });
    return node;
  }

  function throttle(fn, ms) {
    var last = 0;
    return function () {
      var now = Date.now();
      if (now - last >= ms) {
        last = now;
        fn();
      }
    };
  }

  // ── Carousel: prev/next + dots ───────────────────────────────────────
  function enhanceCarousel(carousel) {
    var track = carousel.querySelector(".gallery-track");
    if (!track) return;
    var items = Array.prototype.slice.call(
      track.querySelectorAll(".gallery-item"),
    );
    if (items.length < 2) return;

    function currentIndex() {
      var center = track.scrollLeft + track.clientWidth / 2;
      var best = 0,
        bestDist = Infinity;
      items.forEach(function (item, i) {
        var dist = Math.abs(item.offsetLeft + item.offsetWidth / 2 - center);
        if (dist < bestDist) {
          bestDist = dist;
          best = i;
        }
      });
      return best;
    }

    function scrollTo(i) {
      var item = items[Math.max(0, Math.min(items.length - 1, i))];
      if (item) {
        track.scrollTo({
          left: item.offsetLeft - (track.clientWidth - item.offsetWidth) / 2,
          behavior: "smooth",
        });
      }
    }

    var prev = el("button", "gallery-nav-button gallery-prev", {
      type: "button",
      "aria-label": "Previous image",
    });
    prev.textContent = "‹";
    var next = el("button", "gallery-nav-button gallery-next", {
      type: "button",
      "aria-label": "Next image",
    });
    next.textContent = "›";
    var dotsWrap = el("div", "gallery-dots");

    var dots = items.map(function (_, i) {
      var dot = el("button", "gallery-dot", {
        type: "button",
        "aria-label": "Go to image " + (i + 1),
      });
      dot.addEventListener("click", function () {
        scrollTo(i);
      });
      dotsWrap.appendChild(dot);
      return dot;
    });

    prev.addEventListener("click", function () {
      scrollTo(currentIndex() - 1);
    });
    next.addEventListener("click", function () {
      scrollTo(currentIndex() + 1);
    });

    var nav = el("div", "gallery-nav");
    nav.appendChild(prev);
    nav.appendChild(dotsWrap);
    nav.appendChild(next);
    carousel.appendChild(nav);

    function updateDots() {
      var idx = currentIndex();
      dots.forEach(function (dot, i) {
        dot.setAttribute("aria-current", i === idx ? "true" : "false");
      });
    }
    track.addEventListener("scroll", throttle(updateDots, 100), {
      passive: true,
    });

    // Pin to the first slide. As the async images load they grow the track and
    // the browser drifts a horizontal scroller toward the end — leaving the
    // carousel on the last image with the last dot lit. The pin must be an
    // INSTANT jump: the track's CSS scroll-behavior is smooth, so a plain
    // scrollLeft = 0 animates and gets superseded by the next drift before it
    // lands. We force scroll-behavior: auto for the jump, re-pin as each image
    // settles (that's when the drift happens), and stop the moment the visitor
    // interacts so we never yank them back.
    var pinning = true;
    ["pointerdown", "wheel", "touchstart", "keydown"].forEach(function (ev) {
      track.addEventListener(
        ev,
        function () {
          pinning = false;
        },
        { passive: true, once: true },
      );
    });
    function pinStart() {
      if (!pinning) return;
      var prev = track.style.scrollBehavior;
      track.style.scrollBehavior = "auto";
      track.scrollLeft = 0;
      track.style.scrollBehavior = prev;
      updateDots();
    }
    pinStart();
    items.forEach(function (item) {
      var img = item.querySelector("img");
      if (img && !img.complete)
        img.addEventListener("load", pinStart, { once: true });
    });
    if (document.readyState !== "complete") {
      window.addEventListener("load", pinStart, { once: true });
    }
  }

  // Zoom: open (popovertarget), Esc, and the × button are all native. The
  // only JS touch is click-to-dismiss — once an image is full-screen there's
  // nothing else to do, so a click anywhere on the overlay (the image or the
  // dark area) closes it. Without JS, × and Esc still close it.
  function enhanceZoom(zoom) {
    zoom.addEventListener("click", function () {
      if (typeof zoom.hidePopover === "function") zoom.hidePopover();
    });
  }

  function init() {
    document
      .querySelectorAll("[data-gallery-carousel]")
      .forEach(enhanceCarousel);
    document.querySelectorAll(".gallery-zoom").forEach(enhanceZoom);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

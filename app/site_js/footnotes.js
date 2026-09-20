/* ============== ROE SCRIPT ================
   Roe Script: footnotes
   Version: 1.0.0
   Fingerprint: 5853db65
   Bundled with: Roe v0.4.0

   This file was installed from Roe. Leave this comment in place
   and Admin → Updates will tell you when a newer version ships.
   Edit anything below it freely — Roe can tell, and will never
   overwrite your changes without asking.
   ========================================== */

// Support for multiple backlinks in footnotes
//
// HTML supports one backlink which returns you to the place the footnote
// is mentioned in the text. This adds support for multiple backlinks so a
// footnote can return to all mentions, not just the first.
//
// See docs/04-markdown-extensions.md#known-quirks for the Kramdown details.
//
// Progressive: with no JavaScript the HTML return link still works, and
// nothing here is required to read a footnote.

(function () {
  "use strict";

  document.addEventListener("click", function (event) {
    var reference = event.target.closest
      ? event.target.closest('a.footnote[href^="#fn:"]')
      : null;
    if (!reference) return;

    // Kramdown hangs the id on the wrapping <sup>, not the <a>:
    //   <sup id="fnref:reuse"><a href="#fn:reuse" class="footnote">1</a></sup>
    var anchor = reference.id ? reference : reference.closest("sup[id]");
    if (!anchor || !anchor.id) return;

    var noteId = reference.getAttribute("href").slice(1);
    var note = document.getElementById(noteId);
    if (!note) return;

    var backlink = note.querySelector(".footnote-backlink-number");
    if (!backlink) return;

    backlink.setAttribute("href", "#" + anchor.id);
    // The number is no longer necessarily "the first mention", so keep the
    // label honest for anyone on a screen reader.
    backlink.setAttribute("aria-label", "Return to the reference you followed");
  });
})();

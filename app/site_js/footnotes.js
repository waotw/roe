// Footnote backlinks that return you where you came from.
//
// A footnote referenced more than once can only point its leading number at one
// of those mentions, so without help it always sends you back to the first.
// The rendered HTML already handles that on its own: a multiply-referenced note
// carries a return link per mention (see add_footnote_backlinks). This is the
// enhancement on top — click a reference, and that note's number is repointed
// at the mention you actually came from.
//
// See docs/04-markdown-extensions.md#known-quirks for the Kramdown details.
//
// Progressive: with no JavaScript the numbered return links still work, and
// nothing here is required to read a footnote. Single-reference footnotes are
// unaffected either way.
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

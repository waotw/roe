import { Controller } from "@hotwired/stimulus";

// Markdown warnings in the editor.
//
// The rules live server-side in MarkdownDoctor and are never duplicated here —
// two definitions of "what counts as a problem" would disagree, and the CLI,
// this panel, and any future check would drift. This controller only sends the
// textarea's content and renders what comes back.
//
// Checking is automatic: once on connect (which covers page load and the reload
// that follows a save) and then on a pause in typing, at the same cadence as the
// live preview so both land in one beat instead of staggering. There's no Check
// button — the indicator in the tab strip already says what one would tell you.
//
// NOTHING HERE OPENS THE PANEL. A check that popped a panel open mid-sentence
// would shove the writing area down the page while someone was using it. Typing
// moves the dot and, at most, brings the tab into the strip — which costs no
// vertical space, because the table-of-contents tab already sets the row's
// height. Opening is a click, always.
//
// Fix All edits the TEXTAREA, never the file. The editor's existing dirty-check
// lights the save dot, the leave-modal guards navigation, Ctrl+Z undoes it, and
// "changed my mind" is just not saving. No backup mechanism, and no way for a
// fix to damage anything on disk.
//
// SCOPE: mounted on the same element as the editor controller in each edit view,
// so it can reach both the textarea and the tab strip, which are sibling
// subtrees.
const AUTO_CHECK_DELAY = 800; // matches the preview's typing debounce

export default class extends Controller {
  static targets = [
    "toggleRow",
    "arrow",
    "dot",
    "summary",
    "panel",
    "fixableSection",
    "fixableCount",
    "fixableList",
    "manualSection",
    "manualCount",
    "manualList",
    "clean",
    "fixButton",
    "revertButton",
  ];
  static values = { checkUrl: String, fixUrl: String };

  connect() {
    this.beforeFix = null;
    this.writing = false;
    this.autoTimer = null;
    // Content of the last check that completed, so an edit that leaves the body
    // untouched — metadata, mostly — doesn't cost a request.
    this.lastChecked = null;
    // Responses can land out of order; only the newest one may paint.
    this.sequence = 0;

    // Saving reloads the editor. A panel that closed itself every time would be
    // no use for working through a list, so remember it per document — in
    // sessionStorage, which doesn't outlive the tab.
    this.panelStateKey = `roe-markdown-panel-${window.location.pathname}`;
    this.restoredPanel = false;

    this.onInput = this.handleInput.bind(this);
    // On the controller element, not a form. `input` bubbles, and this element
    // is an ancestor of the textarea, so it can't miss. Looking the form up by
    // querySelector found the *duplicate* form instead — it comes first in the
    // document and the textarea isn't inside it — so nothing ever fired and the
    // only check that ran was the one below, on load.
    this.element.addEventListener("input", this.onInput);

    this.check();
  }

  disconnect() {
    clearTimeout(this.autoTimer);
    this.element.removeEventListener("input", this.onInput);
  }

  get textarea() {
    return document.getElementById("content-textarea");
  }

  get panelOpen() {
    return !this.panelTarget.classList.contains("hidden");
  }

  // --- checking ------------------------------------------------------------

  handleInput() {
    if (this.writing) return; // our own write, not the writer's
    this.invalidateUndo();
    this.scheduleCheck();
  }

  scheduleCheck() {
    clearTimeout(this.autoTimer);
    this.autoTimer = setTimeout(() => this.check(), AUTO_CHECK_DELAY);
  }

  check() {
    const content = this.textarea?.value;
    if (content == null || content === this.lastChecked) return;

    const seq = ++this.sequence;
    this.post(this.checkUrlValue, { content })
      .then((data) => {
        if (!data || seq !== this.sequence) return;
        this.lastChecked = content;
        // Before render, so it sees the panel as open and keeps the tab.
        this.restorePanel();
        this.render(data.issues);
      })
      .catch(() => {}); // a failed check leaves the last known state alone
  }

  render(issues) {
    const fixable = issues.filter((i) => i.fixable);
    const manual = issues.filter((i) => !i.fixable);

    this.fill(this.fixableSectionTarget, this.fixableListTarget, this.fixableCountTarget, fixable);
    this.fill(this.manualSectionTarget, this.manualListTarget, this.manualCountTarget, manual);

    this.cleanTarget.classList.toggle("hidden", issues.length > 0);
    // Fix All belongs to the fixable section, so it goes when that section does.
    this.fixButtonTarget.classList.toggle("hidden", fixable.length === 0);

    this.showStatus(fixable.length, manual.length);
    // The tab is the panel's handle, so it stays while the panel is open — a
    // document that goes clean with the panel showing shouldn't have the panel's
    // own control pulled out from under it. It leaves when the writer closes it.
    this.toggleRowTarget.classList.toggle(
      "hidden",
      issues.length === 0 && !this.panelOpen,
    );
  }

  fill(section, list, count, issues) {
    section.classList.toggle("hidden", issues.length === 0);
    if (issues.length === 0) return;

    count.textContent = `(${issues.length})`;
    // Sorted by line so the list reads in document order within its section.
    list.innerHTML = [...issues]
      .sort((a, b) => a.line - b.line)
      .map((issue) => this.rowFor(issue))
      .join("");
  }

  // No per-row "fixable" tag — the section heading says which is which.
  rowFor(issue) {
    return `<div class="flex gap-2">
      <button type="button" data-action="click->markdown-doctor#jumpTo"
              data-line="${issue.line}"
              class="text-blue-700 hover:underline shrink-0 cursor-pointer">line ${issue.line}</button>
      <span class="text-gray-800">${this.escape(issue.message)}</span>
    </div>`;
  }

  // Amber for problems rather than red: red reads as broken, and a post with a
  // list-spacing warning still publishes. Amber is already this editor's "worth
  // a look" — it's what the save dot uses for unsaved changes.
  showStatus(fixableCount, manualCount) {
    const total = fixableCount + manualCount;

    this.dotTarget.classList.remove("bg-gray-300"); // the pre-first-check state
    this.dotTarget.classList.toggle("bg-amber-500", total > 0);
    this.dotTarget.classList.toggle("bg-green-500", total === 0);

    if (total === 0) {
      this.setSummary("markdown looks good");
      return;
    }

    const parts = [];
    if (fixableCount) parts.push(`${fixableCount} fixable`);
    if (manualCount) parts.push(`${manualCount} to look at`);
    this.setSummary(parts.join(", "));
  }

  // --- fixing --------------------------------------------------------------

  fixAll() {
    const textarea = this.textarea;
    if (!textarea) return;

    // Send the CURRENT text, not whatever the last check saw — the writer may
    // have typed since. The server re-lints before fixing for the same reason,
    // which is also why a slightly stale panel can't produce a bad edit.
    this.post(this.fixUrlValue, { content: textarea.value })
      .then((data) => {
        if (!data) return;

        this.beforeFix = textarea.value;
        this.setContent(textarea, data.content);

        // The server just told us what's left in the text it returned, so record
        // it as checked; re-asking would be the same question.
        this.lastChecked = data.content;
        this.sequence++; // outrun any check still in flight from before the fix
        this.revertButtonTarget.classList.remove("hidden");
        this.render(data.remaining);
      })
      .catch(() => this.setSummary("fix failed"));
  }

  revert() {
    if (this.beforeFix == null) return;

    this.setContent(this.textarea, this.beforeFix);
    this.beforeFix = null;
    this.revertButtonTarget.classList.add("hidden");
    this.check();
  }

  // Typing after a fix retires the undo: restoring the pre-fix text would throw
  // away that typing too, so it's no longer the inverse of anything. Ctrl+Z
  // still walks back through both.
  invalidateUndo() {
    if (this.beforeFix == null) return;

    this.beforeFix = null;
    this.revertButtonTarget.classList.add("hidden");
  }

  // Assigning `value` doesn't fire `input`, and the editor's dirty-check, table
  // of contents and auto-resize all hang off that event — so dispatch it, or the
  // save dot never lights and the writer thinks nothing changed.
  //
  // That event also reaches our own input handler, which would read our write as
  // the writer typing. The flag says "this one was us".
  //
  // contentChanged is separate and deliberate. An open preview tab follows the
  // textarea, but on a debounce meant for typing — and a fix isn't typing: it's
  // one click, with nothing after it to end the pause. This says "the content
  // changed in one go", so the editor can push the preview immediately instead
  // of inferring it from a synthetic keystroke.
  setContent(textarea, content) {
    this.writing = true;
    try {
      textarea.value = content;
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
      this.dispatch("contentChanged", { target: textarea });
    } finally {
      this.writing = false;
    }
  }

  // --- panel ---------------------------------------------------------------

  togglePanel() {
    if (this.panelOpen) this.closePanel();
    else this.openPanel();
  }

  // Reopen where the last page load left off. Deliberately not openPanel: that
  // asks the toolbar to scroll itself into view, which on a fresh load would
  // yank the page down before anyone had looked at it. It also doesn't write
  // the key back — restoring isn't a decision, it's the same decision.
  restorePanel() {
    if (this.restoredPanel) return;
    this.restoredPanel = true;
    if (sessionStorage.getItem(this.panelStateKey) !== "1") return;

    this.panelTarget.classList.remove("hidden");
    this.arrowTarget.textContent = "▼";
  }

  openPanel() {
    this.panelTarget.classList.remove("hidden");
    this.arrowTarget.textContent = "▼";
    sessionStorage.setItem(this.panelStateKey, "1");

    // Dispatched from the PANEL, not this.element. The sticky toolbar is a
    // descendant of the element this controller is mounted on — it has to be,
    // for the controller to see both the textarea and the tab strip — and
    // Stimulus events bubble upward, so a dispatch from this.element would
    // travel away from the toolbar rather than through it. The panel is inside
    // the toolbar, so `markdown-doctor:opened` reaches it on the way up.
    this.dispatch("opened", { target: this.panelTarget });
  }

  // Also wired to the table-of-contents tab: the two share this space, and only
  // one is open at a time. Closing is where a clean document finally drops its
  // tab, which render() keeps alive for as long as the panel is showing.
  closePanel() {
    this.panelTarget.classList.add("hidden");
    this.arrowTarget.textContent = "▶";
    sessionStorage.removeItem(this.panelStateKey);
    if (!this.cleanTarget.classList.contains("hidden")) {
      this.toggleRowTarget.classList.add("hidden");
    }
  }

  // --- navigation ----------------------------------------------------------

  jumpTo(event) {
    const line = parseInt(event.currentTarget.dataset.line, 10);
    const textarea = this.textarea;
    if (!textarea || Number.isNaN(line)) return;

    const lines = textarea.value.split("\n");
    const offset = lines
      .slice(0, line - 1)
      .reduce((sum, l) => sum + l.length + 1, 0);

    textarea.focus();
    textarea.setSelectionRange(offset, offset + (lines[line - 1]?.length || 0));

    // The textarea grows to fit its content (overflow-hidden), so the page
    // scrolls rather than the field — estimate from line height.
    const lineHeight = parseFloat(getComputedStyle(textarea).lineHeight) || 20;
    window.scrollTo({
      top: textarea.offsetTop + (line - 1) * lineHeight - window.innerHeight / 3,
      behavior: "smooth",
    });
  }

  // --- plumbing ------------------------------------------------------------

  setSummary(text) {
    this.summaryTarget.textContent = text;
  }

  post(url, body) {
    return fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token":
          document.querySelector('meta[name="csrf-token"]')?.content || "",
        "X-Requested-With": "XMLHttpRequest",
      },
      body: JSON.stringify(body),
    }).then((r) => (r.ok ? r.json() : null));
  }

  escape(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }
}

// The live markdown editor: CodeMirror 6 standing in for #content-textarea.
//
// The textarea stays in the form, hidden, and stays the thing everything else
// talks to. Nine controllers read and write it — the toolbar, the four block
// builders, site links, the markdown check, the media picker, draft recovery —
// and none of them had to change. Instead, the textarea's own properties are
// pointed at the editor:
//
//   value, selectionStart/End, setSelectionRange, setRangeText, focus
//       read and write the CodeMirror document and selection
//   document.execCommand("insertText")
//       becomes a CodeMirror change, so every button is one undo step
//   input / focus / blur / select events
//       are fired on the textarea, as a real one would fire them
//   Enter and Tab
//       are handed to the textarea's own keydown listeners first, so list,
//       quote and footnote continuation is the same code in both editors
//
// The textarea's real value is kept in step on every change, so the form
// submits exactly the text in the editor, byte for byte. Nothing is converted:
// it's markdown in, markdown out.
//
// If this module fails to load, the textarea is never hidden — the fallback is
// the old editor, not a blank page.

import {
  EditorState,
  EditorSelection,
  Compartment,
  Annotation,
  Transaction,
  Prec,
} from "@codemirror/state";
import {
  EditorView,
  keymap,
  drawSelection,
  dropCursor,
  highlightSpecialChars,
  placeholder,
} from "@codemirror/view";
import {
  history,
  historyKeymap,
  defaultKeymap,
  insertNewline,
  isolateHistory,
} from "@codemirror/commands";
import { syntaxHighlighting } from "@codemirror/language";
import { search, searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { markdown, roeHighlightStyle } from "markdown_editor/syntax";
import { livePreview } from "markdown_editor/live_preview";
import { roeBlocks } from "markdown_editor/roe_blocks";
import { footnotePaste, footnoteAt, footnoteContinuation } from "markdown_editor/footnotes";

// Marks a change made by assigning .value or calling setRangeText. A real
// textarea fires no input event for those, so neither do we.
const programmatic = Annotation.define();

const nativeValue = Object.getOwnPropertyDescriptor(
  HTMLTextAreaElement.prototype,
  "value",
);

export const MODES = ["live", "source"];

function modeExtensions(mode, blocksUrl) {
  // roe-md-editor is here too, not added with classList: CodeMirror rewrites
  // the editor's class attribute when it reconfigures (switching mode, for
  // one), so a class set from outside disappears — and every rule in the
  // MARKDOWN EDITOR section with it.
  const attrs = EditorView.editorAttributes.of({
    class: `roe-md-editor roe-md-${mode}`,
  });
  if (mode === "source") return [attrs];
  return [attrs, livePreview, roeBlocks({ checkUrl: blocksUrl })];
}

// ── document.execCommand ──────────────────────────────────────────────────
// Patched once, for whichever editor has focus. Anything else — a different
// command, or focus somewhere that isn't an editor — goes to the browser.
const activeBridges = new Set();
let originalExecCommand = null;

function installExecCommand() {
  if (originalExecCommand) return;
  originalExecCommand = document.execCommand;
  document.execCommand = function (command, showUI, value) {
    if (command === "insertText") {
      for (const bridge of activeBridges) {
        if (bridge.owns(document.activeElement)) {
          bridge.insertText(String(value ?? ""));
          return true;
        }
      }
    }
    return originalExecCommand.call(document, command, showUI, value);
  };
}

function uninstallExecCommand() {
  if (!originalExecCommand || activeBridges.size) return;
  document.execCommand = originalExecCommand;
  originalExecCommand = null;
}

// ── The editor ────────────────────────────────────────────────────────────

export class MarkdownEditor {
  // textarea   the #content-textarea to stand in for
  // mode       "live" or "source"
  // blocksUrl  POST endpoint for Roe-anji block checks (optional)
  // commands   { bold, italic, strike, link } → functions; the toolbar's own
  //            methods, so a shortcut and a click do exactly the same thing
  constructor({ textarea, mode = "live", blocksUrl = null, commands = {} }) {
    this.textarea = textarea;
    this.commands = commands;
    this.blocksUrl = blocksUrl;
    this.modeCompartment = new Compartment();
    this.mode = MODES.includes(mode) ? mode : "live";
    this.cachedDoc = null;
    this.cachedText = "";

    this.view = new EditorView({
      state: EditorState.create({
        doc: nativeValue.get.call(textarea),
        extensions: this.extensions(),
      }),
    });
    // Lets editor_controller and markdown_doctor reach the editor without
    // importing it: `textarea.roeEditor?.revealLine(n)`. Present means "the
    // live editor is in charge"; absent means the plain textarea.
    textarea.roeEditor = this;

    textarea.after(this.view.dom);
    textarea.style.display = "none";
    this.installShims();
    activeBridges.add(this);
    installExecCommand();
  }

  extensions() {
    const forward = (key, shiftKey = false) => () => this.forwardKey(key, shiftKey);
    const command = (name) => () => {
      const fn = this.commands[name];
      if (!fn) return false;
      fn();
      return true;
    };

    return [
      // Ours first, so Mod-i is italic rather than CodeMirror's
      // "select parent syntax", and Enter tries list continuation before a
      // plain newline.
      Prec.high(
        keymap.of([
          {
            key: "Enter",
            run: (view) => this.forwardKey("Enter") || insertNewline(view),
            shift: insertNewline,
          },
          { key: "Tab", run: forward("Tab"), shift: forward("Tab", true) },
          { key: "Mod-b", run: command("bold") },
          { key: "Mod-i", run: command("italic") },
          { key: "Mod-k", run: command("link") },
          { key: "Mod-~", run: command("strike") },
          { key: "Mod-Shift-`", run: command("strike") },
          { key: "Mod-e", run: command("toggleMode") },
        ]),
      ),
      history(),
      drawSelection(),
      dropCursor(),
      highlightSpecialChars(),
      search({ top: false }),
      highlightSelectionMatches(),
      keymap.of([...searchKeymap, ...historyKeymap, ...defaultKeymap]),
      markdown(),
      footnotePaste,
      syntaxHighlighting(roeHighlightStyle),
      EditorView.lineWrapping,
      // Room below the last line, so it can be scrolled up past the drawer at
      // the bottom of the window and written with space beneath it — what the
      // textarea's pb-96 did. Set through CodeMirror's theme rather than
      // application.css: CodeMirror's own padding on .cm-content is more
      // specific and quietly wins over a plain stylesheet rule.
      EditorView.theme({
        ".cm-content": { padding: "0.25rem 0.25rem var(--roe-md-bottom-space, 50vh)" },
      }),
      placeholder(this.textarea.getAttribute("placeholder") || ""),
      EditorView.contentAttributes.of({
        spellcheck: "true",
        autocorrect: "on",
        autocapitalize: "sentences",
        "aria-label": "Content",
      }),
      this.modeCompartment.of(modeExtensions(this.mode, this.blocksUrl)),
      // Keep the caret clear of the sticky toolbar at the top and the action
      // drawer at the bottom when the window scrolls to it.
      EditorView.scrollMargins.of(() => this.margins()),
      EditorView.updateListener.of((update) => this.onUpdate(update)),
      EditorView.domEventHandlers({
        focus: () => {
          // editor_controller remembers the last focused field (for restoring
          // focus after a save) by watching focusin for textareas.
          this.fire("focusin", FocusEvent, { bubbles: true });
          this.fire("focus", FocusEvent);
        },
        blur: () => this.fire("blur", FocusEvent),
      }),
    ];
  }

  // ── Keeping the textarea in step ────────────────────────────────────────

  onUpdate(update) {
    if (update.docChanged) {
      nativeValue.set.call(this.textarea, this.text);
      const quiet = update.transactions.every((tr) => tr.annotation(programmatic));
      if (!quiet) this.fire("input", Event, { bubbles: true });
    }
    if (update.selectionSet && !update.docChanged) {
      this.fire("select", Event, { bubbles: true });
    }
  }

  fire(type, EventClass, init = {}) {
    this.textarea.dispatchEvent(new EventClass(type, init));
  }

  get text() {
    const doc = this.view.state.doc;
    if (doc !== this.cachedDoc) {
      this.cachedDoc = doc;
      this.cachedText = doc.toString();
    }
    return this.cachedText;
  }

  owns(element) {
    return element === this.textarea || this.view.contentDOM.contains(element);
  }

  // ── Footnotes (see footnotes.js) ────────────────────────────────────────

  // { label, from, to } for the note the caret is in, or null.
  footnoteAt(pos = this.view.state.selection.main.head) {
    return footnoteAt(this.view.state, pos);
  }

  // The indent a new line at the caret needs to stay in its note, or null.
  footnoteContinuation(pos = this.view.state.selection.main.head) {
    return footnoteContinuation(this.view.state, pos);
  }

  // ── Scrolling to a place in the document ────────────────────────────────
  // The window scrolls, not the editor, so "show line 40" means "scroll the
  // window until line 40 is where the writer's eye is". CodeMirror knows the
  // real height of every line — headings, images, collapsed blocks, wrapped
  // paragraphs, and lines it hasn't drawn yet — so nothing here estimates.

  // { top, bottom }: what covers the window's top and bottom edges once the
  // page has scrolled. The sticky toolbar's lower half collapses on the way
  // down and opens on the way up — animated, mid-jump — so the top margin is
  // its full open height, not whatever it measures this frame. Otherwise the
  // same line lands in a different place depending on scroll direction.
  margins() {
    const host = this.textarea.closest('[data-controller~="markdown-editor"]');
    const toolbar = host?.querySelector('[data-controller~="sticky-toolbar"]');
    const collapsible = toolbar?.querySelector('[data-sticky-toolbar-target="collapsible"]');
    const toolbarHeight = toolbar
      ? toolbar.offsetHeight - (collapsible?.offsetHeight || 0) + (collapsible?.scrollHeight || 0)
      : 0;
    const drawer = document.querySelector('[data-controller~="editor-drawer"]');
    return {
      top: Math.min(toolbarHeight, window.innerHeight / 2) + 8,
      bottom: (drawer?.offsetHeight || 0) + 16,
    };
  }

  // Scroll so `pos` sits a third of the way down the visible writing area.
  // Positions below the toolbar, so a jump never lands a heading under it.
  revealPos(pos, { at = 1 / 3 } = {}) {
    const clamped = this.clamp(pos);
    const block = this.view.lineBlockAt(clamped);
    const docTop = this.view.documentTop; // window-relative top of the document
    const lineTop = window.scrollY + docTop + block.top;
    const { top, bottom } = this.margins();
    const visible = window.innerHeight - top - bottom;
    const target = lineTop - top - visible * at;
    window.scrollTo({ top: Math.max(0, target), behavior: "instant" });
  }

  // 1-based line number, as the markdown check reports them.
  lineStart(lineNumber) {
    const doc = this.view.state.doc;
    const n = Math.max(1, Math.min(lineNumber, doc.lines));
    return doc.line(n);
  }

  // Put the caret (or a selection) somewhere and bring it into view, with
  // focus — the one call for every "jump to" in the editor. Instant, not
  // smooth: see settle().
  goTo(anchor, head = anchor, options = {}) {
    const a = this.clamp(anchor);
    const h = this.clamp(head);
    this.view.dispatch({ selection: EditorSelection.single(a, h) });
    this.view.focus({ preventScroll: true });
    this.settle(Math.min(a, h), options);
  }

  // Lines that haven't been drawn yet only have an estimated height, so the
  // first scroll toward a far line lands near it, not on it. Drawing them
  // corrects the heights, which moves the line; place it again, and repeat
  // until it stops moving. Usually two or three frames.
  settle(pos, options = {}, onDone = null) {
    const token = (this.settleToken = {});
    let last = null;
    let frames = 0;
    const step = () => {
      if (token !== this.settleToken) return; // a newer jump took over
      this.revealPos(pos, options);
      const now = window.scrollY;
      if (now === last || ++frames > 10) return onDone?.();
      last = now;
      requestAnimationFrame(() => requestAnimationFrame(step));
    };
    step();
  }

  goToLine(lineNumber, { select = false, ...options } = {}) {
    const line = this.lineStart(lineNumber);
    this.goTo(line.from, select ? line.to : line.from, options);
  }

  clamp(pos) {
    const n = Number(pos) || 0;
    return Math.max(0, Math.min(n, this.view.state.doc.length));
  }

  // Enter and Tab go to the textarea's keydown listeners first —
  // editor_controller's list, blockquote and footnote handling, and its
  // indent/outdent. If one of them handles the key it calls preventDefault,
  // and that's our answer. Not bubbled: the real keydown is already on its way
  // up to the document from CodeMirror.
  forwardKey(key, shiftKey) {
    const event = new KeyboardEvent("keydown", {
      key,
      shiftKey,
      bubbles: false,
      cancelable: true,
    });
    this.textarea.dispatchEvent(event);
    return event.defaultPrevented;
  }

  insertText(text) {
    const { state } = this.view;
    this.view.dispatch(
      state.replaceSelection(text),
      // One button press, one undo step — never merged with the typing on
      // either side of it.
      {
        annotations: [
          isolateHistory.of("full"),
          Transaction.userEvent.of("input.type"),
        ],
        scrollIntoView: true,
      },
    );
  }

  // ── The textarea stand-in ───────────────────────────────────────────────

  installShims() {
    const editor = this;
    const ta = this.textarea;
    const define = (name, descriptor) =>
      Object.defineProperty(ta, name, { configurable: true, ...descriptor });

    define("value", {
      get: () => editor.text,
      set: (value) => editor.replaceAll(String(value ?? "")),
    });
    define("selectionStart", {
      get: () => editor.view.state.selection.main.from,
      set: (pos) => {
        const end = Math.max(editor.clamp(pos), editor.view.state.selection.main.to);
        editor.select(pos, end);
      },
    });
    define("selectionEnd", {
      get: () => editor.view.state.selection.main.to,
      set: (pos) => {
        const start = Math.min(editor.view.state.selection.main.from, editor.clamp(pos));
        editor.select(start, pos);
      },
    });
    define("setSelectionRange", {
      value: (start, end = start) => editor.select(start, end, true),
    });
    define("select", {
      value: () => editor.select(0, editor.view.state.doc.length),
    });
    define("setRangeText", {
      value: (text, start, end, mode = "preserve") => {
        const sel = editor.view.state.selection.main;
        const from = editor.clamp(start ?? sel.from);
        const to = editor.clamp(end ?? sel.to);
        let anchor = sel.from;
        let head = sel.to;
        if (mode === "select") [anchor, head] = [from, from + text.length];
        else if (mode === "start") anchor = head = from;
        else if (mode === "end") anchor = head = from + text.length;
        editor.view.dispatch({
          changes: { from, to, insert: text },
          selection: mode === "preserve" ? undefined : { anchor, head },
          annotations: programmatic.of(true),
        });
      },
    });
    define("focus", { value: () => editor.view.focus() });
    define("blur", { value: () => editor.view.contentDOM.blur() });
    // Code that scrolls the window to the caret measures the textarea. Hidden,
    // it has no box; the editor's box is where the text actually is.
    define("getBoundingClientRect", {
      value: () => editor.view.dom.getBoundingClientRect(),
    });
    define("offsetTop", { get: () => editor.view.dom.offsetTop });
    define("offsetHeight", { get: () => editor.view.dom.offsetHeight });
  }

  removeShims() {
    for (const name of [
      "value",
      "selectionStart",
      "selectionEnd",
      "setSelectionRange",
      "select",
      "setRangeText",
      "focus",
      "blur",
      "getBoundingClientRect",
      "offsetTop",
      "offsetHeight",
    ]) {
      delete this.textarea[name];
    }
  }

  select(start, end, scroll = false) {
    const anchor = this.clamp(start);
    const head = this.clamp(end);
    this.view.dispatch({
      selection: EditorSelection.single(anchor, head),
      scrollIntoView: scroll,
    });
  }

  // Assigning .value: change only what differs, so the caret, scroll and undo
  // history survive a fix that touched one line of a long document.
  replaceAll(next) {
    const current = this.text;
    if (next === current) return;
    let start = 0;
    const max = Math.min(current.length, next.length);
    while (start < max && current.charCodeAt(start) === next.charCodeAt(start)) start++;
    let endCur = current.length;
    let endNext = next.length;
    while (
      endCur > start &&
      endNext > start &&
      current.charCodeAt(endCur - 1) === next.charCodeAt(endNext - 1)
    ) {
      endCur--;
      endNext--;
    }
    this.view.dispatch({
      changes: { from: start, to: endCur, insert: next.slice(start, endNext) },
      annotations: programmatic.of(true),
    });
  }

  // ── Modes ───────────────────────────────────────────────────────────────

  setMode(mode) {
    if (!MODES.includes(mode) || mode === this.mode) return;
    this.mode = mode;
    this.view.dispatch({
      effects: this.modeCompartment.reconfigure(modeExtensions(mode, this.blocksUrl)),
    });
  }

  destroy() {
    nativeValue.set.call(this.textarea, this.text);
    this.removeShims();
    delete this.textarea.roeEditor;
    activeBridges.delete(this);
    uninstallExecCommand();
    this.view.destroy();
    this.view.dom.remove();
    this.textarea.style.display = "";
  }
}

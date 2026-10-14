import { Controller } from "@hotwired/stimulus";

// Puts the live markdown editor (app/javascript/markdown_editor) in place of
// the content textarea, and owns the Live / Source switch.
//
// Kept apart from editor_controller on purpose: that controller still talks to
// the textarea, and markdown_editor/editor.js makes the textarea answer for
// the new editor. So the toolbar, the builders, drafts, save and preview all
// work unchanged, and setting `editor.mode: textarea` in content settings
// skips this controller's work entirely and leaves the old editor as it was.
//
// CodeMirror is imported only here, only when needed — it's ~900 KB that no
// other page should pay for.
const MODE_KEY = "roe-editor-mode";

export default class extends Controller {
  static targets = ["textarea", "modeToggle", "modeState", "modeButton", "modeLabel"];
  static values = {
    mode: { type: String, default: "live" }, // live | source | textarea
    blocksUrl: String,
  };

  async connect() {
    if (this.modeValue === "textarea") return;

    const textarea = this.hasTextareaTarget
      ? this.textareaTarget
      : this.element.querySelector("#content-textarea");
    if (!textarea) return;

    let MarkdownEditor;
    try {
      ({ MarkdownEditor } = await import("markdown_editor/editor"));
    } catch (error) {
      // The textarea is still there and still visible: writing carries on in
      // the old editor rather than stopping.
      console.error(
        "[markdown-editor] couldn't load, using the textarea",
        error,
      );
      return;
    }
    if (!this.element.isConnected || this.editor) return;

    // Where the caret was in the textarea before the editor arrived — a
    // restored post-save position, say — carries across.
    const proto = HTMLTextAreaElement.prototype;
    const start = Object.getOwnPropertyDescriptor(
      proto,
      "selectionStart",
    ).get.call(textarea);
    const end = Object.getOwnPropertyDescriptor(proto, "selectionEnd").get.call(
      textarea,
    );
    const hadFocus = document.activeElement === textarea;

    this.editor = new MarkdownEditor({
      textarea,
      mode: this.storedMode,
      blocksUrl: this.blocksUrlValue || null,
      commands: {
        bold: () => this.runEditorCommand("insertBold"),
        italic: () => this.runEditorCommand("insertItalic"),
        strike: () => this.runEditorCommand("insertStrike"),
        link: () => this.runEditorCommand("insertLink"),
        toggleMode: () => this.toggleMode(),
      },
    });

    if (start || end) textarea.setSelectionRange(start, end);
    if (hadFocus) textarea.focus();

    this.showModeToggle();
    this.connectFindButton();
    this.connectFindShortcut();
  }

  // ⌘F (Ctrl+F off the Mac) opens the editor's find and replace from anywhere
  // on the page, not only with the cursor in the editor — otherwise it opens
  // the browser's own find, which can't replace and doesn't see text inside
  // collapsed blocks. Inside the editor and its find panel CodeMirror already
  // handles the key and calls preventDefault, so this leaves those alone.
  // Ctrl+F on a Mac is left alone too: there it moves the cursor one letter.
  connectFindShortcut() {
    const mac = /Mac|iP(hone|ad|od)/.test(navigator.platform);
    this.onFindKey = (event) => {
      if (event.defaultPrevented || event.altKey || event.shiftKey) return;
      if (event.key.toLowerCase() !== "f") return;
      if (mac ? !event.metaKey || event.ctrlKey : !event.ctrlKey || event.metaKey) return;
      if (!this.editor) return;
      event.preventDefault();
      this.editor.openFind();
    };
    document.addEventListener("keydown", this.onFindKey);
  }

  // FIND, at the right of the sticky drawer at the bottom of the window
  // (shared/_editor_drawer). The drawer is outside this controller's element,
  // so the button is found and wired by hand rather than through a target.
  // One editor per page, so the first button is ours.
  connectFindButton() {
    this.findButton = document.querySelector("[data-roe-find-button]");
    if (!this.findButton) return;
    this.onFind = (event) => {
      event.preventDefault();
      this.editor?.openFind();
    };
    this.findButton.addEventListener("click", this.onFind);
    this.findButton.classList.remove("hidden");
  }

  disconnect() {
    if (this.onFindKey) {
      document.removeEventListener("keydown", this.onFindKey);
      this.onFindKey = null;
    }
    if (this.findButton) {
      this.findButton.removeEventListener("click", this.onFind);
      this.findButton.classList.add("hidden");
      this.findButton = null;
    }
    this.editor?.destroy();
    this.editor = null;
  }

  // The toolbar's own methods, so a shortcut and a button do the same thing.
  // The caret is in the editor when a shortcut fires, so any position
  // editor_controller saved on an earlier blur is stale — clear it, which is
  // what the textarea's "has focus" check used to decide.
  runEditorCommand(name) {
    const editor = this.editorController;
    if (!editor || typeof editor[name] !== "function") return;
    editor.lastCursorPosition = null;
    editor[name]({ preventDefault() {}, stopPropagation() {} });
  }

  get editorController() {
    const host = this.element.closest('[data-controller~="editor"]');
    return (
      host &&
      this.application.getControllerForElementAndIdentifier(host, "editor")
    );
  }

  // ── Live / Source ───────────────────────────────────────────────────────

  get storedMode() {
    const stored = localStorage.getItem(MODE_KEY);
    return stored === "live" || stored === "source" ? stored : this.modeValue;
  }

  toggleMode(event) {
    event?.preventDefault();
    if (!this.editor) return;
    const next = this.editor.mode === "live" ? "source" : "live";
    this.editor.setMode(next);
    localStorage.setItem(MODE_KEY, next);
    this.showModeToggle();
    this.editor.view.focus();
  }

  showModeToggle() {
    if (!this.hasModeToggleTarget) return;
    const live = this.editor.mode === "live";
    // The text says which mode is on; the button says what clicking it does.
    this.modeToggleTarget.classList.remove("hidden");
    this.modeToggleTarget.classList.add("inline-flex");
    if (this.hasModeStateTarget) {
      this.modeStateTarget.textContent = live ? "Live mode" : "Source mode";
    }
    if (this.hasModeLabelTarget) {
      this.modeLabelTarget.textContent = live ? "Source" : "Live";
    }
    if (this.hasModeButtonTarget) {
      this.modeButtonTarget.title = live
        ? "Show plain markdown (⌘E)"
        : "Show formatted text (⌘E)";
    }
  }
}

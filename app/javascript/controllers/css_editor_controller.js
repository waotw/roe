import { Controller } from "@hotwired/stimulus";

// The theme editor's code: CodeMirror 6 (theme_editor/editor.js) standing in
// for the form's textarea, background saves, SAVE AS… and find & replace.
//
// The other theme editor controllers on this element use the editor through
// `this.element.cssEditor` (set once it's ready) and two events:
//
//   css-editor:ready   { view }   the editor exists
//   css-editor:change  { text }   after every edit
//
// If the editor can't load, the textarea stays visible and the form still
// saves it: the fallback is a plain editor, not a blank page.
export default class extends Controller {
  static targets = [
    "textarea", "unsavedIndicator", "editorContainer", "saveStatus",
    "saveAsDialog", "saveAsName", "saveAsFile", "saveAsError",
  ];
  static values = { themeName: String, highlight: String, saveAsUrl: String };

  async connect() {
    this.originalContent = this.textareaTarget.value;
    this.hasUnsavedChanges = false;
    this.onBeforeUnload = (e) => {
      if (!this.hasUnsavedChanges) return;
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", this.onBeforeUnload);

    let editor;
    try {
      editor = await import("theme_editor/editor");
    } catch (error) {
      console.error("The theme editor couldn't load; using the plain text box.", error);
      return;
    }
    if (!this.element.isConnected) return;
    this.editorModule = editor;
    this.view = editor.createEditor({
      parent: this.editorContainerTarget,
      textarea: this.textareaTarget,
      onChange: (text) => {
        this.refreshUnsavedIndicator();
        this.dispatch("change", { detail: { text } });
      },
      onSave: () => this.save(),
    });
    this.element.cssEditor = {
      view: this.view,
      text: () => this.view.state.doc.toString(),
      reveal: (from, to, options) => editor.revealRange(this.view, from, to, options),
      setInspectRanges: (ranges) => this.view.dispatch({ effects: editor.setInspectRanges.of(ranges) }),
    };
    this.dispatch("ready", { detail: { view: this.view } });

    if (this.highlightValue) this.highlightReference(this.highlightValue);
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.onBeforeUnload);
    if (this.view) {
      this.textareaTarget.hidden = false;
      this.view.destroy();
    }
    delete this.element.cssEditor;
  }

  text() {
    return this.view ? this.view.state.doc.toString() : this.textareaTarget.value;
  }

  // Arriving from a media file's "Used in" link (?highlight=/media/...):
  // select where the file is used and scroll to it. A mention inside a
  // comment is skipped — the Media page doesn't count those as uses.
  highlightReference(path) {
    const text = this.text();
    const code = text.replace(/\/\*[\s\S]*?\*\//g, (comment) => " ".repeat(comment.length));
    let at = code.indexOf(path);
    if (at === -1) at = text.indexOf(path);
    if (at === -1) return;
    this.editorModule.revealRange(this.view, at, at + path.length, { select: true });
    this.view.focus();
  }

  find() {
    if (!this.view) return;
    this.editorModule.openFind(this.view);
  }

  // Saves in the background: the page doesn't reload, so the cursor, the
  // scroll position and undo all stay as they were. A Save pressed while one
  // is still going runs once that one finishes.
  async save(e) {
    if (e) e.preventDefault();
    if (this.saving) {
      this.saveAgain = true;
      return;
    }

    const content = this.text();
    this.textareaTarget.value = content;
    const form = document.getElementById("theme-form");

    this.saving = true;
    this.showSaveStatus("Saving…", "text-gray-500");
    try {
      const response = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      });
      const result = response.headers.get("Content-Type")?.includes("application/json")
        ? await response.json()
        : null;

      // COPY: save messages
      if (response.ok && result?.saved) {
        this.originalContent = content;
        this.refreshUnsavedIndicator();
        this.showSaveStatus("✓ Saved", "text-green-700", 2000);
        this.dispatch("saved");
      } else if (result?.error) {
        this.showSaveStatus(`Not saved: ${result.error}`, "text-red-700");
      } else {
        // Not JSON back: usually the sign-in page, after the session ran out.
        this.showSaveStatus("Not saved — you may have been signed out. Sign in in another tab, then save again.", "text-red-700");
      }
    } catch {
      this.showSaveStatus("Not saved — Roe couldn't be reached. Your changes are still here; save again.", "text-red-700");
    } finally {
      this.saving = false;
    }

    if (this.saveAgain) {
      this.saveAgain = false;
      this.save();
    }
  }

  // ── SAVE AS… ────────────────────────────────────────────────────────────

  openSaveAs() {
    this.saveAsErrorTarget.textContent = "";
    this.saveAsNameChanged();
    this.saveAsDialogTarget.showModal();
    this.saveAsNameTarget.select();
  }

  closeSaveAs() {
    this.saveAsDialogTarget.close();
  }

  // Shows the file name the typed name becomes, the way the server makes it.
  saveAsNameChanged() {
    const slug = this.saveAsNameTarget.value
      .normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    this.saveAsFileTarget.textContent = slug ? `site/theme/${slug}.css` : "";
  }

  async saveAs(e) {
    e.preventDefault();
    const body = new FormData();
    body.append("name", this.saveAsNameTarget.value);
    body.append("content", this.text());
    try {
      const response = await fetch(this.saveAsUrlValue, {
        method: "POST",
        body,
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        },
        credentials: "same-origin",
      });
      const result = response.headers.get("Content-Type")?.includes("application/json") ? await response.json() : null;
      if (response.ok && result?.saved) {
        // The text went into the new file; leaving this one isn't losing it.
        this.hasUnsavedChanges = false;
        window.location.href = result.url;
      } else {
        // COPY: SAVE AS… failed
        this.saveAsErrorTarget.textContent = result?.error || "Not saved — you may have been signed out.";
      }
    } catch {
      this.saveAsErrorTarget.textContent = "Not saved — Roe couldn't be reached.";
    }
  }

  // ── Leaving ─────────────────────────────────────────────────────────────

  confirmLeave(e) {
    // COPY: leaving with unsaved changes
    if (this.hasUnsavedChanges && !confirm("You have unsaved changes. Leave without saving?")) {
      e.preventDefault();
    } else {
      this.hasUnsavedChanges = false;
    }
  }

  refreshUnsavedIndicator() {
    this.hasUnsavedChanges = this.text() !== this.originalContent;
    this.unsavedIndicatorTarget.classList.toggle("hidden", !this.hasUnsavedChanges);
  }

  showSaveStatus(text, colorClass, hideAfterMs = null) {
    if (!this.hasSaveStatusTarget) return;
    const el = this.saveStatusTarget;
    clearTimeout(this.saveStatusTimer);
    el.textContent = text;
    el.className = colorClass;
    if (hideAfterMs) this.saveStatusTimer = setTimeout(() => (el.textContent = ""), hideAfterMs);
  }
}

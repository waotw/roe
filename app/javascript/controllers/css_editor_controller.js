import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["textarea", "unsavedIndicator", "editorContainer", "saveStatus"];
  static values = {
    themeName: String,
    previewId: String,
    highlight: String,
  };

  connect() {
    console.log("CSS Editor connected");
    this.hasUnsavedChanges = false;
    this.originalContent = this.textareaTarget.value;
    this.previewUpdateTimer = null;

    // Channel to the live preview tab (same id the preview-receiver uses).
    // When the preview opens it pings "preview-ready" so we can sync the
    // current CSS at once, rather than waiting for the next keystroke.
    if (typeof BroadcastChannel !== "undefined") {
      this.previewChannel = new BroadcastChannel(`preview-${this.previewIdValue}`);
      this.previewChannel.onmessage = (event) => {
        if (event.data && event.data.action === "preview-ready") this.pushPreviewCss();
      };
    }

    // Wait for CodeMirror to be available, then initialize
    this.waitForCodeMirror().then(() => {
      this.initCodeMirror();
    });

    // Set up keyboard shortcuts
    document.addEventListener("keydown", this.handleKeyboard.bind(this));

    // Set up beforeunload warning
    window.addEventListener("beforeunload", this.handleBeforeUnload.bind(this));

    // Listen for save trigger to refresh preview
    this.checkForSaveTrigger();
  }

  waitForCodeMirror() {
    return new Promise((resolve) => {
      if (window.CodeMirror) {
        resolve();
      } else {
        // Check every 50ms for up to 5 seconds
        let attempts = 0;
        const checkInterval = setInterval(() => {
          attempts++;
          if (window.CodeMirror) {
            clearInterval(checkInterval);
            resolve();
          } else if (attempts > 100) {
            clearInterval(checkInterval);
            console.error("CodeMirror failed to load after 5 seconds");
            // Show the textarea as fallback
            this.textareaTarget.style.display = "block";
          }
        }, 50);
      }
    });
  }

  initCodeMirror() {
    console.log("Initializing CodeMirror...");
    
    // Hide the original textarea but keep it for form submission
    this.textareaTarget.style.display = "none";

    // Add explicit styling to container
    this.editorContainerTarget.style.border = "1px solid #d1d5db";
    this.editorContainerTarget.style.fontSize = "14px";

    // Initialize CodeMirror 5
    this.editor = window.CodeMirror(this.editorContainerTarget, {
      value: this.originalContent,
      mode: "css",
      theme: "eclipse",
      lineNumbers: true,
      indentUnit: 2,
      tabSize: 2,
      lineWrapping: true,
      extraKeys: {
        "Cmd-S": () => this.save(),
        "Ctrl-S": () => this.save(),
      }
    });
    
    console.log("CodeMirror initialized with theme:", this.editor.getOption("theme"));
    console.log("Editor wrapper classes:", this.editor.getWrapperElement().className);

    // Sync changes to textarea
    this.editor.on('change', () => {
      this.textareaTarget.value = this.editor.getValue();
      this.refreshUnsavedIndicator();

      // Push the edit to the live preview tab (debounced), before save.
      this.schedulePreviewUpdate();
    });

    // Set height
    this.editor.setSize(null, "70vh");

    if (this.highlightValue) this.highlightReference(this.highlightValue);
  }

  // Arriving from a media file's "Used in" link (?highlight=/media/...): put
  // the cursor on where the file is used, selected, and scroll to it. A
  // mention in a comment is skipped — the Media page doesn't count those as
  // uses, so landing on one would point at the wrong place.
  highlightReference(path) {
    const text = this.editor.getValue();
    const code = text.replace(/\/\*[\s\S]*?\*\//g, (comment) => " ".repeat(comment.length));
    let at = code.indexOf(path);
    if (at === -1) at = text.indexOf(path);
    if (at === -1) return;

    const from = this.editor.posFromIndex(at);
    const to = this.editor.posFromIndex(at + path.length);
    this.editor.focus();
    this.editor.setSelection(from, to);
    this.editor.scrollIntoView({ from, to }, Math.round(this.editor.getScrollInfo().clientHeight / 3));
    this.editorContainerTarget.scrollIntoView({ block: "center" });
  }

  handleKeyboard(e) {
    // Cmd/Ctrl+S to save
    if ((e.metaKey || e.ctrlKey) && e.key === "s") {
      e.preventDefault();
      this.save();
    }
  }

  handleBeforeUnload(e) {
    if (this.hasUnsavedChanges) {
      e.preventDefault();
      e.returnValue = "";
      return "";
    }
  }

  // Saves in the background: the page doesn't reload, so the cursor, the
  // scroll position and undo history all stay where they were. A Save
  // pressed while one is still going runs once that one finishes.
  async save(e) {
    if (e) e.preventDefault();
    if (this.saving) {
      this.saveAgain = true;
      return;
    }

    const content = this.editor ? this.editor.getValue() : this.textareaTarget.value;
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

      if (response.ok && result?.saved) {
        this.originalContent = content;
        this.refreshUnsavedIndicator();
        this.showSaveStatus("✓ Saved", "text-green-700", 2000);
        this.broadcastRefresh();
      } else if (result?.error) {
        this.showSaveStatus(`Not saved: ${result.error}`, "text-red-700");
      } else {
        // Not JSON back: usually the sign-in page, after the session ran out.
        this.showSaveStatus("Not saved — you may have been signed out. Sign in in another tab, then save again.", "text-red-700");
      }
    } catch (error) {
      this.showSaveStatus("Not saved — Roe couldn't be reached. Your changes are still here; save again.", "text-red-700");
    } finally {
      this.saving = false;
    }

    if (this.saveAgain) {
      this.saveAgain = false;
      this.save();
    }
  }

  refreshUnsavedIndicator() {
    const current = this.editor ? this.editor.getValue() : this.textareaTarget.value;
    this.hasUnsavedChanges = current !== this.originalContent;
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

  // Debounced live push of the current CSS to the open preview tab, so it
  // updates as you type — the same pre-save auto-refresh posts/pages/products
  // get. Harmless when no preview tab is listening.
  schedulePreviewUpdate() {
    if (!this.previewChannel) return;
    clearTimeout(this.previewUpdateTimer);
    this.previewUpdateTimer = setTimeout(() => this.pushPreviewCss(), 150);
  }

  pushPreviewCss() {
    if (!this.previewChannel || !this.editor) return;
    this.previewChannel.postMessage({ action: "css", css: this.editor.getValue() });
  }

  preview() {
    const previewUrl = `/?preview_theme=${this.themeNameValue}`;
    window.open(previewUrl, this.previewIdValue);
  }

  confirmCancel(e) {
    if (this.hasUnsavedChanges) {
      if (!confirm("You have unsaved changes. Are you sure you want to leave?")) {
        e.preventDefault();
      }
    }
  }

  checkForSaveTrigger() {
    const trigger = document.getElementById("theme-saved-trigger");
    if (trigger) {
      this.broadcastRefresh();
      const savedPosition = sessionStorage.getItem("cssEditorScrollPosition");
      if (savedPosition) {
        setTimeout(() => {
          window.scrollTo(0, parseInt(savedPosition));
          sessionStorage.removeItem("cssEditorScrollPosition");
        }, 0);
      }
    }
  }

  broadcastRefresh() {
    if (typeof BroadcastChannel !== "undefined") {
      const channel = new BroadcastChannel(`preview-${this.previewIdValue}`);
      channel.postMessage({ action: "refresh" });
      channel.close();
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeyboard.bind(this));
    window.removeEventListener("beforeunload", this.handleBeforeUnload.bind(this));
    clearTimeout(this.previewUpdateTimer);
    if (this.previewChannel) this.previewChannel.close();
    if (this.editor) {
      this.editor.toTextArea();
    }
  }
}

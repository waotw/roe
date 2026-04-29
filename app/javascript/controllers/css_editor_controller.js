import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["textarea", "unsavedIndicator", "editorContainer"];
  static values = {
    themeName: String,
    previewId: String,
  };

  connect() {
    console.log("CSS Editor connected");
    this.hasUnsavedChanges = false;
    this.originalContent = this.textareaTarget.value;

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
      const newContent = this.editor.getValue();
      this.textareaTarget.value = newContent;
      this.hasUnsavedChanges = newContent !== this.originalContent;
      
      if (this.hasUnsavedChanges) {
        this.unsavedIndicatorTarget.classList.remove("hidden");
      } else {
        this.unsavedIndicatorTarget.classList.add("hidden");
      }
    });

    // Set height
    this.editor.setSize(null, "70vh");
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

  save(e) {
    if (e) e.preventDefault();

    // Sync CodeMirror content to textarea before saving
    if (this.editor) {
      this.textareaTarget.value = this.editor.getValue();
    }

    const form = document.getElementById("theme-form");
    this.hasUnsavedChanges = false;
    this.unsavedIndicatorTarget.classList.add("hidden");

    // Save scroll position
    sessionStorage.setItem("cssEditorScrollPosition", window.scrollY);

    form.requestSubmit();
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
    if (this.editor) {
      this.editor.toTextArea();
    }
  }
}

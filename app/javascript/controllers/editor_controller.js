import { Controller } from "@hotwired/stimulus";

// Import EditorState directly
if (!window.EditorState || !window.EditorState.saveElement) {
  const EditorState = {
    save(textareaId) {
      const textarea = document.getElementById(textareaId);
      if (!textarea) return;

      const state = {
        cursorPosition: textarea.selectionStart,
        scrollPosition: textarea.scrollTop,
        url: window.location.pathname,
      };

      sessionStorage.setItem(
        `editorState:${window.location.pathname}`,
        JSON.stringify(state),
      );
    },

    saveElement(element) {
      if (!element || !element.id) return;

      console.log(
        "SAVE ELEMENT:",
        element.id,
        "Cursor:",
        element.selectionStart,
      );

      const state = {
        elementId: element.id,
        cursorPosition: element.selectionStart || 0,
        scrollPosition: element.scrollTop || 0,
        url: window.location.pathname,
      };

      console.log("SAVING STATE:", state);

      sessionStorage.setItem(
        `editorState:${window.location.pathname}`,
        JSON.stringify(state),
      );

      console.log(
        "SAVED TO SESSION:",
        sessionStorage.getItem(`editorState:${window.location.pathname}`),
      );
    },

    restore(textareaId) {
      const stateKey = `editorState:${window.location.pathname}`;
      const savedState = sessionStorage.getItem(stateKey);

      console.log("RESTORE - Key:", stateKey);
      console.log("RESTORE - Saved state:", savedState);

      if (!savedState) {
        console.log("RESTORE - No saved state found");
        return;
      }

      const state = JSON.parse(savedState);
      console.log("RESTORE - Parsed state:", state);

      const elementToRestore = state.elementId
        ? document.getElementById(state.elementId)
        : document.getElementById(textareaId);

      console.log(
        "RESTORE - Element to restore:",
        elementToRestore?.id,
        "Expected cursor:",
        state.cursorPosition,
      );

      if (!elementToRestore) {
        console.log("RESTORE - Element not found!");
        return;
      }

      setTimeout(() => {
        if (elementToRestore.scrollTop !== undefined) {
          elementToRestore.scrollTop = state.scrollPosition || 0;
        }

        elementToRestore.focus({ preventScroll: true });

        if (
          elementToRestore.selectionStart !== undefined &&
          state.cursorPosition !== undefined
        ) {
          console.log("RESTORE - Setting cursor to:", state.cursorPosition);
          elementToRestore.setSelectionRange(
            state.cursorPosition,
            state.cursorPosition,
          );
          console.log(
            "RESTORE - Cursor actually at:",
            elementToRestore.selectionStart,
          );
        }

        sessionStorage.removeItem(stateKey);
      }, 50);
    },
  };

  window.EditorState = EditorState;
}

export default class extends Controller {
  static targets = ["textarea", "form", "metadata", "cardMenu", "mediaUpload"];

  static values = {
    resourceType: String,
    resourceId: String,
    previewPath: String,
    collectionTemplate: String,
    asideTemplate: String,
    postLinkTemplate: String,
    pullquoteTemplate: String,
    knownFields: Array,
    defaultAuthor: String,
  };

  connect() {
    console.log("Editor controller connected");

    // Restore EditorState
    window.EditorState.restore("content-textarea");

    // Store original values for dirty checking
    this.originalContent = this.textareaTarget.value;
    this.originalMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    // Setup broadcast channel for preview
    const previewId = `${this.resourceTypeValue}-${this.resourceIdValue}`;
    this.previewChannel = new BroadcastChannel(`preview-${previewId}`);

    // Bind beforeunload handler
    this.beforeUnloadHandler = this.handleBeforeUnload.bind(this);
    window.addEventListener("beforeunload", this.beforeUnloadHandler);

    // Check for saved trigger and broadcast refresh
    const savedTrigger = document.querySelector('[data-trigger="refresh"]');
    if (savedTrigger) {
      this.previewChannel.postMessage({ action: "refresh" });
    }

    // Prevent scroll restoration
    if ("scrollRestoration" in history) {
      history.scrollRestoration = "manual";
    }

    // Add Turbo navigation warning
    this.turboBeforeVisitHandler = this.handleTurboBeforeVisit.bind(this);
    document.addEventListener(
      "turbo:before-visit",
      this.turboBeforeVisitHandler,
    );

    // Track the last focused input/textarea
    this.lastFocusedInput = null;

    this.element.addEventListener("focusin", (e) => {
      if (
        e.target.matches(
          'textarea, input[type="text"], input[type="date"], select',
        )
      ) {
        this.lastFocusedInput = e.target;
      }
    });

    // Restore scrolls at the very end
    requestAnimationFrame(() => {
      const windowScroll = sessionStorage.getItem(
        `scroll:${window.location.pathname}:window`,
      );
      const textareaScroll = sessionStorage.getItem(
        `scroll:${window.location.pathname}:textarea`,
      );

      if (textareaScroll !== null) {
        this.textareaTarget.scrollTop = parseInt(textareaScroll);
        sessionStorage.removeItem(
          `scroll:${window.location.pathname}:textarea`,
        );
      }

      if (windowScroll !== null) {
        window.scrollTo(0, parseInt(windowScroll));
        sessionStorage.removeItem(`scroll:${window.location.pathname}:window`);
      }
    });
  }

  disconnect() {
    console.log("Editor controller disconnected");

    // Clean up event listeners
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    // Close broadcast channel
    if (this.previewChannel) {
      this.previewChannel.close();
    }

    // Remove Turbo handler
    document.removeEventListener(
      "turbo:before-visit",
      this.turboBeforeVisitHandler,
    );

    // Remove metadata change listener
    document.removeEventListener(
      "metadata:changed",
      this.metadataChangeHandler,
    );
  }

  handleTurboBeforeVisit(event) {
    const currentContent = this.textareaTarget.value;
    const currentMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    if (
      currentContent !== this.originalContent ||
      currentMetadata !== this.originalMetadata
    ) {
      if (
        !confirm("You have unsaved changes. Are you sure you want to leave?")
      ) {
        event.preventDefault();

        // Restore focus to the last input that was focused, or default to main textarea
        const elementToFocus = this.lastFocusedInput || this.textareaTarget;
        const cursorPosition = elementToFocus.selectionStart || 0;

        requestAnimationFrame(() => {
          elementToFocus.focus({ preventScroll: true });

          if (elementToFocus.selectionStart !== undefined) {
            elementToFocus.setSelectionRange(cursorPosition, cursorPosition);
          }
        });
      }
    }
  }

  handleMetadataChange(event) {
    // Update the hidden field value and refresh our original metadata reference
    // so subsequent changes are tracked correctly
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField) {
      metadataField.value = event.detail.yaml;
    }
  }

  // ========== FORMATTING ACTIONS ==========

  insertBold(event) {
    event.preventDefault();
    this.wrapSelection("**", "**", "bold text");
  }

  insertItalic(event) {
    event.preventDefault();
    this.wrapSelection("_", "_", "italic text");
  }

  insertStrike(event) {
    event.preventDefault();
    this.wrapSelection("~~", "~~", "struck text");
  }

  insertFootnote(event) {
    event.preventDefault();
    this.wrapSelection("(*", "*)", "footnote text here");
  }

  // ========== CARD ACTIONS ==========

  toggleCardMenu(event) {
    event.preventDefault();
    event.stopPropagation();
    this.cardMenuTarget.classList.toggle("hidden");
  }

  closeCardMenu() {
    if (this.hasCardMenuTarget) {
      this.cardMenuTarget.classList.add("hidden");
    }
  }

  insertCard(event) {
    event.preventDefault();
    const cardType = event.currentTarget.dataset.cardType;

    if (cardType === "pullquote") {
      this.insertCardTemplate(this.pullquoteTemplateValue);
    } else if (cardType === "aside") {
      this.insertCardTemplate(this.asideTemplateValue);
    } else if (cardType === "post-link") {
      this.insertCardTemplate(this.postLinkTemplateValue);
    }

    this.closeCardMenu();
  }

  showPostLinkPrompt(event) {
    event.preventDefault();
    this.closeCardMenu();

    const overlay = document.createElement("div");
    overlay.id = "post-link-modal";
    overlay.className = "fixed inset-0 flex items-center justify-center z-50";
    overlay.style.cssText = "background-color: rgba(0, 0, 0, 0.2);";
    overlay.innerHTML = `
      <div class="bg-white p-6 w-96 border border-gray-400">
        <div class="relative mb-4">
          <input
            type="text"
            id="post-search-input"
            placeholder="Search for a post by title..."
            class="w-full px-3 py-2 border border-gray-300"
          >
          <div id="post-search-results" class="hidden absolute top-full left-0 right-0 mt-1 bg-white border border-gray-300 max-h-60 overflow-y-auto z-10"></div>
        </div>
        <div class="flex justify-end gap-2">
          <button type="button"
                  data-action="click->editor#closePostLinkModal"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Cancel
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    const input = document.getElementById("post-search-input");
    input.focus();

    let searchTimeout;
    input.addEventListener("input", (e) => {
      clearTimeout(searchTimeout);
      const query = e.target.value.trim();

      if (query.length < 2) {
        document.getElementById("post-search-results").classList.add("hidden");
        return;
      }

      searchTimeout = setTimeout(() => this.searchPosts(query), 300);
    });

    // Close on overlay click
    overlay.addEventListener("click", (e) => {
      if (e.target.id === "post-link-modal") {
        this.closePostLinkModal();
      }
    });
  }

  searchPosts(query) {
    const resultsDiv = document.getElementById("post-search-results");

    fetch(`/admin/posts/search?q=${encodeURIComponent(query)}`)
      .then((response) => response.json())
      .then((posts) => {
        if (posts.length === 0) {
          resultsDiv.innerHTML =
            '<div class="p-2 text-gray-500 text-sm">No posts found</div>';
          resultsDiv.classList.remove("hidden");
          return;
        }

        resultsDiv.innerHTML = posts
          .map(
            (post) => `
            <button
              type="button"
              data-action="click->editor#selectPost"
              data-post='${JSON.stringify(post)}'
              class="block w-full text-left px-3 py-2 hover:bg-gray-100 text-sm border-b border-gray-200 last:border-b-0"
            >
              ${post.title}
            </button>
          `,
          )
          .join("");

        resultsDiv.classList.remove("hidden");
      })
      .catch((error) => {
        console.error("Search error:", error);
      });
  }

  selectPost(event) {
    event.preventDefault();
    const postData = JSON.parse(event.currentTarget.dataset.post);
    const slug = postData.url.replace(/^\/posts\//, "");

    let cardTemplate = "```card\ntype: post-link\nstyle: small\n";
    cardTemplate += `post: ${slug}\n`;
    cardTemplate += "```";

    this.textareaTarget.focus({ preventScroll: true });
    document.execCommand("insertText", false, cardTemplate);

    this.closePostLinkModal();
  }

  closePostLinkModal() {
    const modal = document.getElementById("post-link-modal");
    if (modal) {
      modal.remove();
    }
  }

  // ========== COLLECTION ACTION ==========

  insertCollection(event) {
    event.preventDefault();
    const start = this.textareaTarget.selectionStart;
    const collectionTemplate =
      "```collection\n" + this.collectionTemplateValue + "\n```";

    document.execCommand("insertText", false, collectionTemplate);

    const cursorPos = start + "```collection\nheading: ".length;
    this.textareaTarget.setSelectionRange(cursorPos, cursorPos);
  }

  // ========== MEDIA ACTIONS ==========

  triggerMediaUpload(event) {
    event.preventDefault();
    this.mediaUploadTarget.click();
  }

  handleMediaUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    const savedPosition = this.textareaTarget.selectionStart;
    const formData = new FormData();
    formData.append("file", file);

    const token = document.querySelector('meta[name="csrf-token"]').content;

    fetch("/admin/medium", {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
      },
      body: formData,
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.success) {
          this.insertMedia(data.path, file.name, savedPosition);
        } else {
          alert("Upload failed: " + data.error);
        }
      })
      .catch((error) => {
        alert("Upload error: " + error);
      });

    event.target.value = "";
  }

  insertMedia(path, filename, position) {
    const markdown = `![${filename}](${path})`;

    this.textareaTarget.focus({ preventScroll: true });
    this.textareaTarget.setSelectionRange(position, position);

    document.execCommand("insertText", false, markdown);

    const lineHeight = parseInt(
      window.getComputedStyle(this.textareaTarget).lineHeight,
    );
    const lines = this.textareaTarget.value
      .substring(0, this.textareaTarget.selectionStart)
      .split("\n").length;
    this.textareaTarget.scrollTop = (lines - 5) * lineHeight;
  }

  // ========== PREVIEW ACTION ==========

  preview(event) {
    event.preventDefault();
    if (!this.previewPathValue) {
      console.error("Preview path not defined");
      return;
    }

    const url = new URL(this.previewPathValue, window.location.origin);
    const previewId = `${this.resourceTypeValue}-${this.resourceIdValue}`;
    window.open(url.toString(), previewId);
  }

  // ========== FORM ACTIONS ==========

  save(event) {
    // Save the currently focused element
    const elementToSave = this.lastFocusedInput || this.textareaTarget;
    window.EditorState.saveElement(elementToSave);

    // Save scrolls separately with a unique key
    sessionStorage.setItem(
      `scroll:${window.location.pathname}:window`,
      window.scrollY,
    );
    sessionStorage.setItem(
      `scroll:${window.location.pathname}:textarea`,
      this.textareaTarget.scrollTop,
    );

    // Mark content as saved
    this.originalContent = this.textareaTarget.value;
    this.originalMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    // Remove beforeunload handler
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    // Broadcast refresh to preview
    this.previewChannel.postMessage({ action: "refresh" });
  }

  restoreScrollPosition() {
    // EditorState.init() already handles restoration in connect()
    // This method can now just handle window scroll
    const savedWindowScroll = sessionStorage.getItem("windowScrollPosition");

    if (savedWindowScroll !== null) {
      window.scrollTo(0, parseInt(savedWindowScroll));
      sessionStorage.removeItem("windowScrollPosition");
    }
  }

  handleKeydown(event) {
    // Cmd/Ctrl+S to save
    if ((event.metaKey || event.ctrlKey) && event.key === "s") {
      event.preventDefault();
      this.formTarget.requestSubmit();
    }

    // Cmd/Ctrl+P to preview
    if ((event.metaKey || event.ctrlKey) && event.key === "p") {
      event.preventDefault();
      this.preview(event);
    }
  }

  // ========== PUBLISH/UNPUBLISH CONFIRMATIONS ==========

  confirmPublish(event) {
    if (
      !confirm(
        "Publishing this post will save your changes and make it live on your site. Continue?",
      )
    ) {
      event.preventDefault();
      return;
    }
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
  }

  confirmUnpublish(event) {
    if (
      !confirm(
        "Unpublishing this post will save your changes and remove it from your site. Continue?",
      )
    ) {
      event.preventDefault();
      return;
    }
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
  }

  // ========== HELPER METHODS ==========

  wrapSelection(prefix, suffix, placeholder = "") {
    const start = this.textareaTarget.selectionStart;
    const end = this.textareaTarget.selectionEnd;
    const selectedText = this.textareaTarget.value.substring(start, end);

    const content = selectedText || placeholder;
    const insertion = prefix + content + suffix;

    this.textareaTarget.focus({ preventScroll: true });
    document.execCommand("insertText", false, insertion);

    if (!selectedText && placeholder) {
      const selectStart = start + prefix.length;
      const selectEnd = selectStart + placeholder.length;
      this.textareaTarget.setSelectionRange(selectStart, selectEnd);
    }
  }

  insertCardTemplate(template) {
    const start = this.textareaTarget.selectionStart;
    const fullText = "```card\n" + template + "\n```";

    document.execCommand("insertText", false, fullText);

    const placeholderIndex = template.indexOf("__PLACEHOLDER__");
    if (placeholderIndex !== -1) {
      const placeholderStart = start + "```card\n".length + placeholderIndex;
      const placeholderEnd = placeholderStart + "__PLACEHOLDER__".length;
      this.textareaTarget.setSelectionRange(placeholderStart, placeholderEnd);
    } else {
      const cursorPos = start + fullText.length;
      this.textareaTarget.setSelectionRange(cursorPos, cursorPos);
    }
  }

  handleBeforeUnload(event) {
    const currentContent = this.textareaTarget.value;
    const currentMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    if (
      currentContent !== this.originalContent ||
      currentMetadata !== this.originalMetadata
    ) {
      event.preventDefault();
      event.returnValue = "";
    }
  }

  saveScrollPosition() {
    sessionStorage.setItem(
      "editorScrollPosition",
      this.textareaTarget.scrollTop,
    );
    sessionStorage.setItem("windowScrollPosition", window.scrollY);

    // Save cursor/focus for ANY active element
    const activeElement = document.activeElement;
    if (activeElement && activeElement.id) {
      sessionStorage.setItem("editorActiveElementId", activeElement.id);

      // Save cursor position if it's a text input or textarea
      if (activeElement.selectionStart !== undefined) {
        sessionStorage.setItem(
          "editorCursorPosition",
          activeElement.selectionStart,
        );
      }
    }
  }

  // Hide flash notice on input
  hideFlashOnInput() {
    const flashNotice = document.querySelector(".flash-notice");
    if (flashNotice) {
      flashNotice.style.display = "none";
    }
  }

  // Handle visibility changes (for media browser)
  handleVisibilityChange() {
    if (document.hidden) {
      if (typeof window.EditorState !== "undefined") {
        window.EditorState.save("content-textarea");
      }
    } else {
      if (typeof window.EditorState !== "undefined") {
        window.EditorState.restore("content-textarea");
      }
    }
  }

  // Save editor state before browsing media
  saveEditorState() {
    if (typeof window.EditorState !== "undefined") {
      window.EditorState.save("content-textarea");
    }
  }
}

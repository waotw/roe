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

    // Track last cursor position when textarea loses focus
    this.lastCursorPosition = null;

    this.textareaTarget.addEventListener("blur", () => {
      this.lastCursorPosition = this.textareaTarget.selectionStart;
      console.log("[BLUR] Saved cursor position:", this.lastCursorPosition);
    });

    this.textareaTarget.addEventListener("input", () => {
      console.log("[INPUT] Clearing saved position");
      this.lastCursorPosition = null;
    });

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

    // Close card menu on escape or click outside
    this.cardMenuClickHandler = (e) => {
      if (
        this.hasCardMenuTarget &&
        !this.cardMenuTarget.classList.contains("hidden")
      ) {
        // Close if clicking outside the card menu and button
        if (
          !e.target.closest('[data-editor-target="cardMenu"]') &&
          !e.target.closest('[data-action*="toggleCardMenu"]')
        ) {
          this.closeCardMenu();
        }
      }
    };

    this.cardMenuKeyHandler = (e) => {
      if (
        e.key === "Escape" &&
        this.hasCardMenuTarget &&
        !this.cardMenuTarget.classList.contains("hidden")
      ) {
        this.closeCardMenu();
      }
    };

    // Add global keyboard shortcut handler
    this.globalKeydownHandler = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.globalKeydownHandler);

    document.addEventListener("click", this.cardMenuClickHandler);
    document.addEventListener("keydown", this.cardMenuKeyHandler);

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

    // Remove global keyboard handler
    document.removeEventListener("keydown", this.globalKeydownHandler);

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

    document.removeEventListener("click", this.cardMenuClickHandler);
    document.removeEventListener("keydown", this.cardMenuKeyHandler);
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
    this.wrapSelectionWithSavedPosition("**", "**", "bold text");
  }

  insertItalic(event) {
    event.preventDefault();
    this.wrapSelectionWithSavedPosition("_", "_", "italic text");
  }

  insertStrike(event) {
    event.preventDefault();
    this.wrapSelectionWithSavedPosition("~~", "~~", "struck text");
  }

  insertFootnote(event) {
    event.preventDefault();
    this.wrapSelectionWithSavedPosition("(*", "*)", "footnote text here");
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

    // Save cursor position before opening modal
    this.savedCursorBeforeModal = this.textareaTarget.selectionStart;
    console.log(
      "[POST LINK] Saved cursor position:",
      this.savedCursorBeforeModal,
    );

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
                  id="post-link-cancel"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Cancel
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    const input = document.getElementById("post-search-input");
    const resultsDiv = document.getElementById("post-search-results");
    const cancelButton = document.getElementById("post-link-cancel");

    input.focus();

    // Handle cancel button click
    cancelButton.addEventListener("click", () => {
      this.closePostLinkModal();
    });

    let searchTimeout;
    let selectedIndex = -1;

    // Handle clicks on search results
    resultsDiv.addEventListener("click", (e) => {
      const button = e.target.closest("button[data-post]");
      if (button) {
        e.preventDefault();
        const postData = JSON.parse(button.dataset.post);
        this.insertPostLink(postData);
      }
    });

    // Handle arrow keys and enter
    input.addEventListener("keydown", (e) => {
      const buttons = resultsDiv.querySelectorAll("button");

      if (e.key === "ArrowDown") {
        e.preventDefault();
        selectedIndex = Math.min(selectedIndex + 1, buttons.length - 1);
        updateSelection(buttons, selectedIndex);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        selectedIndex = Math.max(selectedIndex - 1, -1);
        updateSelection(buttons, selectedIndex);
      } else if (
        e.key === "Enter" &&
        selectedIndex >= 0 &&
        selectedIndex < buttons.length
      ) {
        e.preventDefault();
        buttons[selectedIndex].click();
      } else if (e.key === "Escape") {
        e.preventDefault();
        this.closePostLinkModal();
      }
    });

    // Update visual selection
    const updateSelection = (buttons, index) => {
      buttons.forEach((btn, i) => {
        if (i === index) {
          btn.classList.add("bg-blue-100");
          btn.scrollIntoView({ block: "nearest" });
        } else {
          btn.classList.remove("bg-blue-100");
        }
      });
    };

    input.addEventListener("input", (e) => {
      clearTimeout(searchTimeout);
      selectedIndex = -1; // Reset selection on new search
      const query = e.target.value.trim();

      if (query.length < 2) {
        resultsDiv.classList.add("hidden");
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
              data-post='${JSON.stringify(post).replace(/'/g, "&apos;")}'
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
    console.log("[SELECT POST] Function called!");
    console.log("[SELECT POST] Event:", event);

    event.preventDefault();
    const postData = JSON.parse(event.currentTarget.dataset.post);
    const slug = postData.url.replace(/^\/posts\//, "");

    console.log("[SELECT POST] Post data:", postData);
    console.log("[SELECT POST] Saved cursor:", this.savedCursorBeforeModal);

    let cardTemplate = "```card\ntype: post-link\nstyle: small\n";
    cardTemplate += `post: ${slug}\n`;
    cardTemplate += "```";

    // Focus textarea and restore saved position
    this.textareaTarget.focus({ preventScroll: true });

    if (
      this.savedCursorBeforeModal !== null &&
      this.savedCursorBeforeModal !== undefined
    ) {
      this.textareaTarget.setSelectionRange(
        this.savedCursorBeforeModal,
        this.savedCursorBeforeModal,
      );
      console.log(
        "[SELECT POST] Restored cursor to:",
        this.savedCursorBeforeModal,
      );
    }

    document.execCommand("insertText", false, cardTemplate);
    console.log("[SELECT POST] Inserted card template");

    this.closePostLinkModal();

    // Clear saved position
    this.savedCursorBeforeModal = null;
  }

  insertPostLink(postData) {
    console.log("[INSERT POST LINK] Called with:", postData);

    const slug = postData.url.replace(/^\/posts\//, "");

    let cardTemplate = "```card\ntype: post-link\nstyle: small\n";
    cardTemplate += `post: ${slug}\n`;
    cardTemplate += "```";

    // Focus textarea and restore saved position
    this.textareaTarget.focus({ preventScroll: true });

    if (
      this.savedCursorBeforeModal !== null &&
      this.savedCursorBeforeModal !== undefined
    ) {
      this.textareaTarget.setSelectionRange(
        this.savedCursorBeforeModal,
        this.savedCursorBeforeModal,
      );
      console.log(
        "[INSERT POST LINK] Restored cursor to:",
        this.savedCursorBeforeModal,
      );
    }

    document.execCommand("insertText", false, cardTemplate);
    console.log("[INSERT POST LINK] Inserted card template");

    this.closePostLinkModal();

    // Clear saved position
    this.savedCursorBeforeModal = null;
  }

  closePostLinkModal() {
    const modal = document.getElementById("post-link-modal");
    if (modal) {
      modal.remove();
    }

    // Restore focus to textarea
    if (this.hasTextareaTarget) {
      this.textareaTarget.focus({ preventScroll: true });
    }
  }

  // ========== COLLECTION ACTION ==========

  insertCollection(event) {
    event.preventDefault();

    console.log("[COLLECTION] START - savedPos:", this.lastCursorPosition);

    // Save position before focusing
    const savedPos = this.lastCursorPosition;

    // Focus textarea
    this.textareaTarget.focus({ preventScroll: true });

    // Restore saved position if we have one
    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
      console.log("[COLLECTION] Restored position to:", savedPos);
    }

    const start = this.textareaTarget.selectionStart;
    console.log("[COLLECTION] Inserting at position:", start);

    const collectionTemplate =
      "```collection\n" + this.collectionTemplateValue + "\n```";
    document.execCommand("insertText", false, collectionTemplate);

    // Look for __PLACEHOLDER__ in the template
    const placeholderIndex =
      this.collectionTemplateValue.indexOf("__PLACEHOLDER__");
    if (placeholderIndex !== -1) {
      // Select the placeholder text
      const placeholderStart =
        start + "```collection\n".length + placeholderIndex;
      const placeholderEnd = placeholderStart + "__PLACEHOLDER__".length;
      this.textareaTarget.setSelectionRange(placeholderStart, placeholderEnd);
      console.log(
        "[COLLECTION] Selected placeholder at:",
        placeholderStart,
        "-",
        placeholderEnd,
      );
    } else {
      // No placeholder, just put cursor at the end
      const cursorPos = start + collectionTemplate.length;
      this.textareaTarget.setSelectionRange(cursorPos, cursorPos);
      console.log("[COLLECTION] No placeholder, cursor at end:", cursorPos);
    }

    // Clear saved position
    this.lastCursorPosition = null;
    console.log("[COLLECTION] END");
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
      console.log("[KEYBOARD] Cmd/Ctrl+S pressed, submitting form");
      this.formTarget.requestSubmit();
    }

    // Cmd/Ctrl+P to preview
    if ((event.metaKey || event.ctrlKey) && event.key === "p") {
      event.preventDefault();
      console.log("[KEYBOARD] Cmd/Ctrl+P pressed, opening preview");
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

  wrapSelectionWithSavedPosition(prefix, suffix, placeholder = "") {
    console.log("[WRAP] START - savedPos:", this.lastCursorPosition);

    // Check if textarea currently has focus and a selection
    const hasFocus = document.activeElement === this.textareaTarget;
    const hasSelection =
      this.textareaTarget.selectionStart !== this.textareaTarget.selectionEnd;

    console.log("[WRAP] Has focus:", hasFocus, "Has selection:", hasSelection);

    // Only use saved position if textarea doesn't have focus AND no selection
    const shouldUseSavedPosition =
      !hasFocus && !hasSelection && this.lastCursorPosition !== null;

    // Focus textarea first
    this.textareaTarget.focus({ preventScroll: true });

    // Restore saved position only if needed
    if (shouldUseSavedPosition) {
      this.textareaTarget.setSelectionRange(
        this.lastCursorPosition,
        this.lastCursorPosition,
      );
      console.log("[WRAP] Restored position to:", this.lastCursorPosition);
    }

    const start = this.textareaTarget.selectionStart;
    const end = this.textareaTarget.selectionEnd;
    console.log("[WRAP] Selection range:", start, "-", end);

    const selectedText = this.textareaTarget.value.substring(start, end);
    const content = selectedText || placeholder;
    const insertion = prefix + content + suffix;

    document.execCommand("insertText", false, insertion);
    console.log("[WRAP] Inserted:", insertion);

    if (!selectedText && placeholder) {
      const selectStart = start + prefix.length;
      const selectEnd = selectStart + placeholder.length;
      this.textareaTarget.setSelectionRange(selectStart, selectEnd);
    }

    // Clear saved position
    this.lastCursorPosition = null;
    console.log("[WRAP] END");
  }

  // Keep the old method for backwards compatibility if needed elsewhere
  wrapSelection(prefix, suffix, placeholder = "") {
    this.wrapSelectionWithSavedPosition(prefix, suffix, placeholder);
  }

  insertCardTemplate(template) {
    console.log("[CARD] START - savedPos:", this.lastCursorPosition);

    // Save position before focusing
    const savedPos = this.lastCursorPosition;

    // Focus textarea
    this.textareaTarget.focus({ preventScroll: true });

    // Restore saved position if we have one
    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
      console.log("[CARD] Restored position to:", savedPos);
    }

    const start = this.textareaTarget.selectionStart;
    console.log("[CARD] Inserting at position:", start);

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

    // Clear saved position
    this.lastCursorPosition = null;
    console.log("[CARD] END");
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

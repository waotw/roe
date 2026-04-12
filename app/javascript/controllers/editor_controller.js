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
  static targets = [
    "textarea",
    "form",
    "metadata",
    "cardMenu",
    "mediaUpload",
    "tocPanel",
    "tocContent",
    "tocArrow",
  ];

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
    highlightMedia: String,
  };

  connect() {
    console.log("Editor controller connected");
    this.isSaving = false;

    // Initialize TOC
    this.updateTOC();

    // Close TOC on typing
    this.textareaTarget.addEventListener("input", () => {
      if (
        this.hasTocPanelTarget &&
        !this.tocPanelTarget.classList.contains("hidden")
      ) {
        this.tocPanelTarget.classList.add("hidden");
        if (this.hasTocArrowTarget) {
          this.tocArrowTarget.textContent = "▶";
        }
      }
    });

    // Auto-expand textarea
    this.autoExpandTextarea();
    this.textareaTarget.addEventListener("input", () =>
      this.autoExpandTextarea(),
    );

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

    // Combined Enter key handler for footnotes and lists
    this.enterHandler = (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        // Try list handling first (more common)
        if (this.handleListEnter(e)) return;
        // Then try footnote handling
        if (this.handleFootnoteEnter(e)) return;
      }
    };
    this.textareaTarget.addEventListener("keydown", this.enterHandler);

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

    // Handle Tab key for indentation
    this.tabHandler = (e) => {
      if (e.key === "Tab") {
        e.preventDefault();

        if (e.shiftKey) {
          // Shift+Tab: Remove indentation
          this.outdentLine();
        } else {
          // Tab: Add indentation (2 spaces for Markdown)
          document.execCommand("insertText", false, "  ");
        }
      }
    };
    this.textareaTarget.addEventListener("keydown", this.tabHandler);

    this.cardMenuKeyHandler = (e) => {
      if (
        e.key === "Escape" &&
        this.hasCardMenuTarget &&
        !this.cardMenuTarget.classList.contains("hidden")
      ) {
        this.closeCardMenu();
      }
    };

    // Store original values for dirty checking
    this.originalContent = this.textareaTarget.value;
    this.originalMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    // Listen for metadata changes from metadata_editor_controller
    this.metadataChangeHandler = this.handleMetadataChange.bind(this);
    document.addEventListener("metadata:changed", this.metadataChangeHandler);

    // CHECK BUTTON ON INITIAL LOAD
    this.checkInitialButtonState();

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

    this.scrollBeforeInput = window.scrollY;

    this.textareaTarget.addEventListener("input", () => {
      const savedScroll = this.scrollBeforeInput;

      requestAnimationFrame(() => {
        const currentScroll = window.scrollY;
        const scrollDelta = currentScroll - savedScroll;

        // Only allow small downward scrolls (typing at bottom)
        if (scrollDelta > 0 && scrollDelta < 150) {
          // Natural bottom scroll, allow it and add margin
          window.scrollBy({ top: 0, behavior: "instant" }); // Add 30px extra margin
        } else {
          // Lock scroll
          window.scrollTo({ top: savedScroll, behavior: "instant" });
        }

        this.scrollBeforeInput = window.scrollY;
      });
    });

    let scrollTimeout;
    window.addEventListener("scroll", () => {
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(() => {
        this.scrollBeforeInput = window.scrollY;
      }, 100);
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

    if (this.hasHighlightMediaValue && this.highlightMediaValue) {
      setTimeout(() => this.highlightMediaReference(), 100);
    }
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

    // Remove combined enter handler
    if (this.enterHandler) {
      this.textareaTarget.removeEventListener("keydown", this.enterHandler);
    }

    // Remove tab handler
    if (this.tabHandler) {
      this.textareaTarget.removeEventListener("keydown", this.tabHandler);
    }

    // Remove footnote done button if it exists
    this.removeFootnoteDoneButton();

    document.removeEventListener("click", this.cardMenuClickHandler);
    document.removeEventListener("keydown", this.cardMenuKeyHandler);
  }

  handleTurboBeforeVisit(event) {
    // If we're in the middle of saving, don't show warning
    if (this.isSaving) {
      console.log("[TURBO] Saving in progress, skipping dirty check");
      return;
    }

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
    // Update the hidden field value
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField) {
      metadataField.value = event.detail.yaml;
    }

    // Update publish/unpublish button based on status
    this.updatePublishButton(event.detail.yaml);
  }

  updatePublishButton(yaml) {
    // Parse status from YAML
    const statusMatch = yaml.match(/^status:\s*["']?(\w+)["']?$/m);
    if (!statusMatch) return;

    const newStatus = statusMatch[1];

    // Find the button
    const publishButton = this.element.querySelector(
      '[data-action*="confirmPublish"]',
    );
    const unpublishButton = this.element.querySelector(
      '[data-action*="confirmUnpublish"]',
    );

    // Determine current button state
    const currentlyShowingPublish = publishButton !== null;
    const shouldShowPublish = newStatus === "draft";

    // Only update if state changed
    if (currentlyShowingPublish === shouldShowPublish) return;

    // Get the button container
    const buttonContainer =
      publishButton?.parentElement || unpublishButton?.parentElement;
    if (!buttonContainer) return;

    // Get post ID from existing button
    const postId =
      publishButton?.dataset.editorPostId ||
      unpublishButton?.closest("form")?.action.match(/\/posts\/(\d+)\//)?.[1];
    if (!postId) return;

    // Get requirements from existing button (if publish button exists)
    const requiresAudience =
      publishButton?.dataset.editorRequiresAudience || "false";
    const requiresPublishedTo =
      publishButton?.dataset.editorRequiresPublishedTo || "false";

    // Build new button HTML
    const authToken =
      document.querySelector('meta[name="csrf-token"]')?.content || "";

    if (shouldShowPublish) {
      // Show Publish button
      buttonContainer.innerHTML = `
        <form action="/admin/posts/${postId}/publish"
              method="post"
              data-turbo="false"
              data-action="submit->editor#confirmPublish"
              data-editor-requires-audience="${requiresAudience}"
              data-editor-requires-published-to="${requiresPublishedTo}"
              data-editor-post-id="${postId}">
          <input type="hidden" name="_method" value="patch">
          <input type="hidden" name="authenticity_token" value="${authToken}">
          <button type="submit"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Publish
          </button>
        </form>
      `;
    } else {
      // Show Unpublish button
      buttonContainer.innerHTML = `
        <form action="/admin/posts/${postId}/unpublish"
              method="post"
              data-turbo="false"
              data-action="submit->editor#confirmUnpublish">
          <input type="hidden" name="_method" value="patch">
          <input type="hidden" name="authenticity_token" value="${authToken}">
          <button type="submit"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Unpublish
          </button>
        </form>
      `;
    }
  }

  checkInitialButtonState() {
    // Get initial metadata from the form
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField && metadataField.value) {
      this.updatePublishButton(metadataField.value);
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

    const content = this.textareaTarget.value;
    const footnoteMatches = [...content.matchAll(/\[\^(\d+)\]/g)];
    const footnoteNumbers = footnoteMatches.map((m) => parseInt(m[1]));
    const nextNumber =
      footnoteNumbers.length > 0 ? Math.max(...footnoteNumbers) + 1 : 1;

    const originalPos = this.textareaTarget.selectionStart;
    console.log("[FOOTNOTE] Original position:", originalPos);

    this.textareaTarget.focus({ preventScroll: true });
    this.textareaTarget.setSelectionRange(originalPos, originalPos);

    const reference = `[^${nextNumber}]`;
    document.execCommand("insertText", false, reference);

    const positionAfterReference = originalPos + reference.length;

    // Jump to end of document
    const currentContent = this.textareaTarget.value;
    const endPos = currentContent.length;

    const needsNewlines = !currentContent.endsWith("\n\n");
    const separator = needsNewlines ? "\n\n" : "";
    const footnoteDefinition = `${separator}[^${nextNumber}]: `;

    this.textareaTarget.setSelectionRange(endPos, endPos);
    document.execCommand("insertText", false, footnoteDefinition);

    const cursorPos = this.textareaTarget.value.length;
    this.textareaTarget.setSelectionRange(cursorPos, cursorPos);
    this.textareaTarget.scrollTop = this.textareaTarget.scrollHeight;
    this.scrollBeforeInput = window.scrollY;

    this.showFootnoteDoneButton(positionAfterReference);
  }

  handleFootnoteEnter(event) {
    const cursorPos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;
    const beforeCursor = content.substring(0, cursorPos);
    const lines = beforeCursor.split("\n");
    const currentLineNumber = lines.length - 1;

    let footnoteDefLine = null;

    for (let i = currentLineNumber; i >= 0; i--) {
      const line = lines[i];
      if (line.match(/^\[\^\d+\]:/)) {
        footnoteDefLine = line;
        break;
      }
      if (line.trim() === "") continue;
      if (line.match(/^\s+/)) continue;
      break;
    }

    if (footnoteDefLine) {
      event.preventDefault();

      // Kramdown expects 4 spaces for continuation, not visual alignment
      const indent = "    "; // Always 4 spaces for Kramdown compatibility

      document.execCommand("insertText", false, "\n" + indent);
      console.log("[FOOTNOTE] Auto-indented with 4 spaces (Kramdown standard)");
      return true;
    }

    return false;
  }

  showFootnoteDoneButton(returnPosition) {
    // Remove any existing done button
    this.removeFootnoteDoneButton();

    // Create floating done button
    const doneButton = document.createElement("button");
    doneButton.type = "button";
    doneButton.id = "footnote-done-button";
    doneButton.className =
      "fixed bottom-8 right-10 z-50 uppercase text-base px-1.5 py-2 border border-gray-800 bg-blue-200 hover:bg-blue-300 font-mono rounded-xs";
    doneButton.innerHTML = "✓ Done with Footnote";
    doneButton.dataset.returnPosition = returnPosition;

    // Click handler to return to original position
    doneButton.addEventListener("click", (e) => {
      e.preventDefault();
      this.returnFromFootnote(returnPosition);
    });

    // Add to page
    document.body.appendChild(doneButton);

    // Auto-remove on escape key
    this.footnoteDoneKeyHandler = (e) => {
      if (e.key === "Escape") {
        this.returnFromFootnote(returnPosition);
      }
    };
    document.addEventListener("keydown", this.footnoteDoneKeyHandler);
  }

  returnFromFootnote(returnPosition) {
    console.log("[FOOTNOTE] Returning to position:", returnPosition);

    // Focus textarea and jump back
    this.textareaTarget.focus({ preventScroll: false });
    this.textareaTarget.setSelectionRange(returnPosition, returnPosition);

    // Scroll to make cursor visible
    const lineHeight = parseInt(
      window.getComputedStyle(this.textareaTarget).lineHeight,
    );
    const lines = this.textareaTarget.value
      .substring(0, returnPosition)
      .split("\n").length;
    this.textareaTarget.scrollTop = Math.max(0, (lines - 10) * lineHeight);

    // Update scroll lock position
    setTimeout(() => {
      this.scrollBeforeInput = window.scrollY;
    }, 100);

    // Remove done button
    this.removeFootnoteDoneButton();
  }

  removeFootnoteDoneButton() {
    const existingButton = document.getElementById("footnote-done-button");
    if (existingButton) {
      existingButton.remove();
    }

    // Remove escape key handler
    if (this.footnoteDoneKeyHandler) {
      document.removeEventListener("keydown", this.footnoteDoneKeyHandler);
      this.footnoteDoneKeyHandler = null;
    }
  }

  insertUnorderedList(event) {
    event.preventDefault();

    const savedPos = this.lastCursorPosition;
    this.textareaTarget.focus({ preventScroll: true });

    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
    }

    const pos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;

    // Check if we're at the start of a line
    const beforeCursor = content.substring(0, pos);
    const needsNewline =
      beforeCursor.length > 0 && !beforeCursor.endsWith("\n");

    const insertion = (needsNewline ? "\n" : "") + "- ";
    document.execCommand("insertText", false, insertion);

    this.lastCursorPosition = null;
  }

  insertOrderedList(event) {
    event.preventDefault();

    const savedPos = this.lastCursorPosition;
    this.textareaTarget.focus({ preventScroll: true });

    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
    }

    const pos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;

    // Check if we're at the start of a line
    const beforeCursor = content.substring(0, pos);
    const needsNewline =
      beforeCursor.length > 0 && !beforeCursor.endsWith("\n");

    const insertion = (needsNewline ? "\n" : "") + "1. ";
    document.execCommand("insertText", false, insertion);

    this.lastCursorPosition = null;
  }

  handleListEnter(event) {
    const cursorPos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;
    const beforeCursor = content.substring(0, cursorPos);
    const afterCursor = content.substring(cursorPos);

    // Get current line
    const lines = beforeCursor.split("\n");
    const currentLine = lines[lines.length - 1];

    // Only handle Enter at end of line
    const nextChar = afterCursor[0];
    const atEndOfLine = !nextChar || nextChar === "\n";
    if (!atEndOfLine) return false;

    // Check for unordered list: "- " or "  - "
    const unorderedMatch = currentLine.match(/^(\s*)-\s+(.*)$/);
    if (unorderedMatch) {
      event.preventDefault();
      const indent = unorderedMatch[1];
      const itemContent = unorderedMatch[2];

      if (itemContent.trim() === "") {
        // Empty list item - exit list (remove the "- ")
        const lineStart = beforeCursor.length - currentLine.length;
        this.textareaTarget.value =
          content.substring(0, lineStart) + indent + afterCursor;
        this.textareaTarget.selectionStart = this.textareaTarget.selectionEnd =
          lineStart + indent.length;
      } else {
        // Has content - create next list item
        document.execCommand("insertText", false, "\n" + indent + "- ");
      }
      return true;
    }

    // Check for ordered list: "1. " or "  2. "
    const orderedMatch = currentLine.match(/^(\s*)(\d+)\.\s+(.*)$/);
    if (orderedMatch) {
      event.preventDefault();
      const indent = orderedMatch[1];
      const currentNumber = parseInt(orderedMatch[2]);
      const itemContent = orderedMatch[3];

      if (itemContent.trim() === "") {
        // Empty list item - exit list
        const lineStart = beforeCursor.length - currentLine.length;
        this.textareaTarget.value =
          content.substring(0, lineStart) + indent + afterCursor;
        this.textareaTarget.selectionStart = this.textareaTarget.selectionEnd =
          lineStart + indent.length;
      } else {
        // Has content - create next list item
        const nextNumber = currentNumber + 1;
        document.execCommand(
          "insertText",
          false,
          "\n" + indent + nextNumber + ". ",
        );
      }
      return true;
    }

    return false; // Not a list
  }

  outdentLine() {
    const cursorPos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;
    const beforeCursor = content.substring(0, cursorPos);
    const afterCursor = content.substring(cursorPos);

    // Get current line
    const lines = beforeCursor.split("\n");
    const currentLine = lines[lines.length - 1];

    // Check if line starts with spaces (remove up to 2 spaces)
    const match = currentLine.match(/^( {1,2})/);
    if (match) {
      const spacesToRemove = match[1].length;
      const lineStart = beforeCursor.length - currentLine.length;

      // Remove the spaces
      const newContent =
        content.substring(0, lineStart) +
        currentLine.substring(spacesToRemove) +
        afterCursor;

      this.textareaTarget.value = newContent;
      this.textareaTarget.selectionStart = this.textareaTarget.selectionEnd =
        cursorPos - spacesToRemove;

      console.log(`[OUTDENT] Removed ${spacesToRemove} spaces`);
    }
  }

  insertLink(event) {
    event.preventDefault();

    // Check if textarea has focus and selection
    const hasFocus = document.activeElement === this.textareaTarget;
    const hasSelection =
      this.textareaTarget.selectionStart !== this.textareaTarget.selectionEnd;

    const shouldUseSavedPosition =
      !hasFocus && !hasSelection && this.lastCursorPosition !== null;

    // Focus textarea
    this.textareaTarget.focus({ preventScroll: true });

    // Restore saved position if needed
    if (shouldUseSavedPosition) {
      this.textareaTarget.setSelectionRange(
        this.lastCursorPosition,
        this.lastCursorPosition,
      );
    }

    const start = this.textareaTarget.selectionStart;
    const end = this.textareaTarget.selectionEnd;
    const selectedText = this.textareaTarget.value.substring(start, end);

    // Use selected text or placeholder
    const linkText = selectedText || "link text";
    const insertion = `[${linkText}]()`;

    document.execCommand("insertText", false, insertion);

    // Position cursor between the parentheses
    const cursorPos = start + `[${linkText}](`.length;
    this.textareaTarget.setSelectionRange(cursorPos, cursorPos);

    // Clear saved position
    this.lastCursorPosition = null;
  }

  // ========== GALLERY ACTIONS ==========

  insertGallery(event) {
    event.preventDefault();

    const savedPos = this.lastCursorPosition;
    this.textareaTarget.focus({ preventScroll: true });

    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
    }

    const start = this.textareaTarget.selectionStart;
    const galleryTemplate = "```gallery\n__PLACEHOLDER__\n```";

    document.execCommand("insertText", false, galleryTemplate);

    const placeholderStart = start + "```gallery\n".length;
    const placeholderEnd = placeholderStart + "__PLACEHOLDER__".length;
    this.textareaTarget.setSelectionRange(placeholderStart, placeholderEnd);

    this.lastCursorPosition = null;
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

  insertPaywall(event) {
    event.preventDefault();

    const savedPos = this.lastCursorPosition;
    this.textareaTarget.focus({ preventScroll: true });

    if (savedPos !== null) {
      this.textareaTarget.setSelectionRange(savedPos, savedPos);
    }

    const start = this.textareaTarget.selectionStart;

    const paywallTemplate = [
      "```form",
      "for: paid_content",
      "text: This is premium content. Upgrade to continue reading.",
      "button-text: Become a paid member",
      "```",
    ].join("\n");

    document.execCommand("insertText", false, paywallTemplate);

    // Position cursor at end of inserted block
    const cursorPos = start + paywallTemplate.length;
    this.textareaTarget.setSelectionRange(cursorPos, cursorPos);

    this.lastCursorPosition = null;
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

  // ========== TOC METHODS ==========

  toggleTOC(event) {
    event.preventDefault();

    if (this.hasTocPanelTarget) {
      this.tocPanelTarget.classList.toggle("hidden");

      // Restore full background when opening
      if (!this.tocPanelTarget.classList.contains("hidden")) {
        this.tocPanelTarget.style.backgroundColor = "";
      }

      // Update arrow
      if (this.hasTocArrowTarget) {
        this.tocArrowTarget.textContent =
          this.tocPanelTarget.classList.contains("hidden") ? "▶" : "▼";
      }

      this.textareaTarget.focus({ preventScroll: true });
    }
  }

  updateTOC() {
    if (!this.hasTocContentTarget) return;

    const content = this.textareaTarget.value;
    const lines = content.split("\n");

    // Find all headings (h2-h4)
    const headings = [];
    lines.forEach((line, index) => {
      const match = line.match(/^(#{2,4})\s+(.+)$/);
      if (match) {
        const level = match[1].length;
        const text = match[2];
        const slug = this.generateSlug(text);
        headings.push({ level, text, slug, lineIndex: index });
      }
    });

    if (headings.length === 0) {
      this.tocContentTarget.innerHTML =
        '<div class="text-gray-500">No headings found</div>';
      return;
    }

    /// Render headings with hash symbols
    this.tocContentTarget.innerHTML = headings
      .map((heading) => {
        const hashes = "#".repeat(heading.level); // ##, ###, or ####
        return `
        <div class="flex items-center justify-between py-1 hover:bg-gray-100 px-2 -mx-2 group">
          <button type="button"
                  data-action="click->editor#jumpToHeading"
                  data-line="${heading.lineIndex}"
                  class="flex-1 text-left truncate">
            <span class="text-gray-400 mr-2">${hashes}</span><span class="text-gray-700 hover:text-gray-900">${this.escapeHtml(heading.text)}</span>
          </button>
          <button type="button"
                  data-action="click->editor#copyHeadingLink"
                  data-slug="${heading.slug}"
                  class="ml-2 uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem] opacity-0 group-hover:opacity-100 transition-opacity">
            Copy
          </button>
        </div>
      `;
      })
      .join("");
  }

  jumpToHeading(event) {
    event.preventDefault();
    const lineIndex = parseInt(event.currentTarget.dataset.line);

    const lines = this.textareaTarget.value.split("\n");
    const charPosition =
      lines
        .slice(0, lineIndex)
        .reduce((sum, line) => sum + line.length + 1, 0) +
      lines[lineIndex].length;

    this.textareaTarget.setSelectionRange(charPosition, charPosition);
    this.textareaTarget.focus();

    // Fade TOC background after jumping
    if (
      this.hasTocPanelTarget &&
      !this.tocPanelTarget.classList.contains("hidden")
    ) {
      this.tocPanelTarget.style.backgroundColor = "rgba(249, 250, 251, 0.3)";
    }

    // Update scroll lock position
    setTimeout(() => {
      this.scrollBeforeInput = window.scrollY;
    }, 50);
  }

  restoreTocOpacity() {
    if (this.hasTocPanelTarget) {
      this.tocPanelTarget.style.backgroundColor = ""; // Remove inline style, return to bg-gray-50
    }
  }

  copyHeadingLink(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const slug = button.dataset.slug;

    // Get post ID from controller value
    const postId = this.resourceIdValue;
    const fullUrl = `${window.location.origin}/p/${postId}#${slug}`;

    navigator.clipboard.writeText(fullUrl).then(() => {
      // Save original classes
      const originalClasses = button.className;
      const originalText = button.textContent;

      // Success animation
      button.className =
        "ml-2 uppercase text-xs px-1.5 py-0 border border-green-800 bg-green-200 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]";
      button.textContent = "✓ Copied!";

      // Reset after 1.5 seconds
      setTimeout(() => {
        button.className = originalClasses;
        button.textContent = originalText;
      }, 1500);
    });
  }

  generateSlug(text) {
    return text
      .toLowerCase()
      .replace(/[^\w\s-]/g, "")
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-")
      .trim();
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
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
    console.log("[SAVE] Starting save...");

    // Mark that we're saving to skip dirty checks
    this.isSaving = true;

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

    // Get the current metadata from the hidden field (most up-to-date)
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField) {
      this.originalMetadata = metadataField.value;
    }

    // Remove beforeunload handler
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    // Broadcast refresh to preview
    this.previewChannel.postMessage({ action: "refresh" });

    console.log("[SAVE] Dirty state cleared, form will submit");
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

  showPublishModal(
    requiresAudience,
    requiresPublishedTo,
    currentAudience,
    currentPublishedTo,
  ) {
    // Get post ID from form data
    const postId = event.target.dataset.editorPostId;

    if (!postId) {
      console.error("Post ID not found");
      return;
    }

    // Build query params
    const params = new URLSearchParams({
      requires_audience: requiresAudience,
      requires_published_to: requiresPublishedTo,
      current_audience: currentAudience || "",
      current_published_to: currentPublishedTo || "",
    });

    // Load modal via Turbo Frame
    const modalUrl = `/admin/posts/${postId}/publish_modal?${params}`;

    // Create modal container if it doesn't exist
    let modalContainer = document.getElementById("publish-modal-container");
    if (!modalContainer) {
      modalContainer = document.createElement("turbo-frame");
      modalContainer.id = "publish-modal-container";
      document.body.appendChild(modalContainer);
    }

    // Load the modal
    modalContainer.src = modalUrl;
  }

  confirmPublish(event) {
    event.preventDefault();

    const form = event.target;

    // Always show modal - set saving state first
    this.isSaving = true;
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    // Get current metadata values from the editor
    const metadataEditor = document.querySelector(
      '[data-controller="metadata-editor"]',
    );
    const audienceField = metadataEditor?.querySelector(
      '[data-metadata-field="audience"]',
    );
    const publishedToField = metadataEditor?.querySelector(
      '[data-metadata-field="published_to"]',
    );

    const currentAudience = audienceField?.value || "";
    const currentPublishedTo = publishedToField?.value || "";

    // Check which fields are enabled
    const requiresAudience = form.dataset.editorRequiresAudience === "true";
    const requiresPublishedTo =
      form.dataset.editorRequiresPublishedTo === "true";

    this.showPublishModal(
      requiresAudience,
      requiresPublishedTo,
      currentAudience,
      currentPublishedTo,
    );
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

    this.isSaving = true;
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
  }

  // ========== HELPER METHODS ==========

  autoExpandTextarea() {
    this.textareaTarget.style.height = "auto";
    this.textareaTarget.style.height = this.textareaTarget.scrollHeight + "px";
  }

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

  highlightMediaReference() {
    const mediaPath = this.highlightMediaValue;
    const content = this.textareaTarget.value;

    // First, try to find it in content
    let position = content.indexOf(mediaPath);

    if (position !== -1) {
      // Found in content - highlight there
      this.textareaTarget.setSelectionRange(position, position);
      this.textareaTarget.focus();
      this.textareaTarget.style.caretColor = "red";

      const resetCursor = () => {
        this.textareaTarget.style.caretColor = "";
      };

      this.textareaTarget.addEventListener("click", resetCursor, {
        once: true,
      });
      this.textareaTarget.addEventListener("keydown", resetCursor, {
        once: true,
      });

      console.log("[HIGHLIGHT] Found in content at position:", position);
      return;
    }

    // Not in content - check metadata fields
    const metadataFields = [
      "image",
      "audio",
      "video",
      "thumbnail",
      "cover",
      "poster",
    ];

    for (const fieldName of metadataFields) {
      const input = document.querySelector(
        `input[name="metadata[${fieldName}]"], input[id*="${fieldName}"]`,
      );

      if (input && input.value === mediaPath) {
        // Found in metadata field - highlight the input
        input.focus();
        input.select();
        input.style.caretColor = "red";
        input.style.borderColor = "red";

        const resetInput = () => {
          input.style.caretColor = "";
          input.style.borderColor = "";
        };

        input.addEventListener("click", resetInput, { once: true });
        input.addEventListener("keydown", resetInput, { once: true });
        input.addEventListener("blur", resetInput, { once: true });

        // Scroll the input into view
        input.scrollIntoView({ behavior: "smooth", block: "center" });

        console.log("[HIGHLIGHT] Found in metadata field:", fieldName);
        return;
      }
    }

    console.log("[HIGHLIGHT] Media not found in content or metadata");
  }

  // ========== TEST EMAIL METHODS ==========

  sendTestEmail(event) {
    event.preventDefault();

    const url = event.currentTarget.dataset.editorTestEmailUrl;
    const defaultEmail = event.currentTarget.dataset.editorDefaultEmail || "";

    this.showTestEmailModal(url, defaultEmail);
  }

  showTestEmailModal(url, defaultEmail) {
    const overlay = document.createElement("div");
    overlay.id = "test-email-modal";
    overlay.className = "fixed inset-0 flex items-center justify-center z-50";
    overlay.style.cssText = "background-color: rgba(0, 0, 0, 0.2);";

    overlay.innerHTML = `
      <div class="bg-white p-6 w-96 border border-gray-400">
        <h3 class="font-mono text-sm mb-4 uppercase">Send Test Newsletter</h3>
        <input
          type="email"
          id="test-email-input"
          value="${this.escapeHtml(defaultEmail)}"
          placeholder="your@email.com"
          class="w-full px-3 py-2 border border-gray-300 mb-4 font-mono text-sm"
        >
        <div id="test-email-status" class="mb-4 text-sm hidden"></div>
        <div class="flex justify-end gap-2">
          <button type="button"
                  id="test-email-cancel"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Cancel
          </button>
          <button type="button"
                  id="test-email-send"
                  class="uppercase text-xs px-1.5 py-0 border border-blue-600 bg-blue-200 hover:bg-blue-300 text-blue-700 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Send
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    const input = document.getElementById("test-email-input");
    const sendButton = document.getElementById("test-email-send");
    const cancelButton = document.getElementById("test-email-cancel");
    const statusDiv = document.getElementById("test-email-status");

    input.focus();
    input.select();

    // Send button
    sendButton.addEventListener("click", () => {
      const email = input.value.trim();
      if (!email) {
        this.showTestEmailError(statusDiv, "Please enter an email address");
        return;
      }

      this.sendTestEmailRequest(url, email, statusDiv, sendButton);
    });

    // Cancel button
    cancelButton.addEventListener("click", () => this.closeTestEmailModal());

    // Keyboard shortcuts
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        sendButton.click();
      } else if (e.key === "Escape") {
        this.closeTestEmailModal();
      }
    });

    // Close on overlay click
    overlay.addEventListener("click", (e) => {
      if (e.target.id === "test-email-modal") {
        this.closeTestEmailModal();
      }
    });
  }

  async sendTestEmailRequest(url, email, statusDiv, sendButton) {
    sendButton.disabled = true;
    sendButton.textContent = "Sending...";

    try {
      const token = document.querySelector('meta[name="csrf-token"]').content;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
        },
        body: JSON.stringify({ email: email }),
      });

      const data = await response.json();

      if (data.success) {
        this.showTestEmailSuccess(statusDiv, `✓ Test email sent to ${email}!`);
        setTimeout(() => this.closeTestEmailModal(), 2000);
      } else {
        this.showTestEmailError(
          statusDiv,
          data.error || "Failed to send email",
        );
        sendButton.disabled = false;
        sendButton.textContent = "Send";
      }
    } catch (error) {
      this.showTestEmailError(statusDiv, "Network error: " + error.message);
      sendButton.disabled = false;
      sendButton.textContent = "Send";
    }
  }

  showTestEmailSuccess(statusDiv, message) {
    statusDiv.textContent = message;
    statusDiv.className =
      "mb-4 text-sm text-green-700 bg-green-50 p-2 border border-green-300 rounded-xs";
    statusDiv.classList.remove("hidden");
  }

  showTestEmailError(statusDiv, message) {
    statusDiv.textContent = message;
    statusDiv.className =
      "mb-4 text-sm text-red-700 bg-red-50 p-2 border border-red-300 rounded-xs";
    statusDiv.classList.remove("hidden");
  }

  closeTestEmailModal() {
    const modal = document.getElementById("test-email-modal");
    if (modal) {
      modal.remove();
    }

    if (this.hasTextareaTarget) {
      this.textareaTarget.focus({ preventScroll: true });
    }
  }

  showResendModal(event) {
    const button = event.currentTarget;
    const postId = button.dataset.postId;
    const modalUrl = `/admin/posts/${postId}/resend_modal`;

    let modalContainer = document.getElementById("resend-modal-container");
    if (!modalContainer) {
      modalContainer = document.createElement("div");
      modalContainer.id = "resend-modal-container";
      document.body.appendChild(modalContainer);
    }

    fetch(modalUrl)
      .then((response) => response.text())
      .then((html) => {
        modalContainer.innerHTML = html;
      });
  }

  toggleAllMembers(event) {
    const button = event.currentTarget;
    const additionalMembers = document.getElementById("additional-members");

    if (additionalMembers.classList.contains("hidden")) {
      additionalMembers.classList.remove("hidden");
      button.textContent = "Show fewer members";
    } else {
      additionalMembers.classList.add("hidden");
      const memberCount = button.textContent.match(/\d+/)[0];
      button.textContent = `Show all ${memberCount} members`;
    }
  }

  closeResendModal(event) {
    // Only close on successful submission
    if (event.detail.success !== false) {
      const modalContainer = document.getElementById("resend-modal-container");
      if (modalContainer) {
        modalContainer.innerHTML = "";
      }

      // Show "Sending..." state
      const postId = this.resourceIdValue;
      const statusDiv = document.getElementById(`newsletter-status-${postId}`);
      if (statusDiv) {
        statusDiv.innerHTML = `
          <hr class="text-gray-300 my-2">
          <div class="flex items-start gap-2">
            <svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18.9844 13.3496" class="w-4 h-4 mt-0.5 flex-shrink-0">
              <path d="M2.49023 13.3496L16.4062 13.3496C17.793 13.3496 18.623 12.5391 18.623 10.8984L18.623 2.46094C18.623 0.820312 17.7832 0.00976562 16.1328 0.00976562L2.2168 0.00976562C0.820312 0.00976562 0 0.820312 0 2.46094L0 10.8984C0 12.5391 0.830078 13.3496 2.49023 13.3496ZM2.43164 12.0215C1.73828 12.0215 1.33789 11.6406 1.33789 10.8984L1.33789 2.45117C1.73789 1.71875 1.73828 1.33789 2.43164 1.33789L16.1816 1.33789C16.8848 1.33789 17.2852 1.71875 17.2852 2.46094L17.2852 10.9082C17.2852 11.6406 16.8848 12.0215 16.1816 12.0215ZM13.5645 5.13672L15.5078 5.13672C15.8496 5.13672 16.1035 4.88281 16.1035 4.54102L16.1035 3.125C16.1035 2.7832 15.8496 2.5293 15.5078 2.5293L13.5645 2.5293C13.2227 2.5293 12.9688 2.7832 12.9688 3.125L12.9688 4.54102C12.9688 4.88281 13.2227 5.13672 13.5645 5.13672ZM6.36719 7.95898L12.2461 7.95898C12.5488 7.95898 12.7832 7.72461 12.7832 7.42188C12.7832 7.12891 12.5488 6.89453 12.2461 6.89453L6.36719 6.89453C6.07422 6.89453 5.83008 7.12891 5.83008 7.42188C5.83008 7.72461 6.07422 7.95898 6.36719 7.95898ZM6.36719 10.0293L10.791 10.0293C11.0938 10.0293 11.3281 9.78516 11.3281 9.49219C11.3281 9.19922 11.0938 8.95508 10.791 8.95508L6.36719 8.95508C6.07422 8.95508 5.83008 9.19922 5.83008 9.49219C5.83008 9.78516 6.07422 10.0293 6.36719 10.0293Z" fill="currentColor"/>
            </svg>
            <div class="flex-1">
              <div>
                <strong class="text-blue-600">Sending newsletter...</strong>
                <span class="ml-2 inline-block">
                  <svg class="animate-spin h-4 w-4 text-blue-600 inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                </span>
              </div>
            </div>
          </div>
        `;

        // After 3 seconds, reload the page to show updated numbers
        setTimeout(() => {
          window.location.reload();
        }, 3000);
      }
    }
  }

  refreshNewsletterStatus(event) {
    const postId = this.resourceIdValue;
    const frame = document.getElementById(`newsletter-status-${postId}`);
    if (frame) {
      frame.src = `/admin/posts/${postId}/newsletter_status`;
      frame.reload();
    }
  }

  confirmProductPublish(event) {
    event.preventDefault();

    // Get current metadata
    const metadataTextarea = document.querySelector(
      '[data-metadata-editor-target="yamlTextarea"]',
    );
    const metadataYaml = metadataTextarea ? metadataTextarea.value : "";

    // Parse to check for SKU
    let hasSku = false;
    try {
      const lines = metadataYaml.split("\n");
      hasSku = lines.some((line) => line.match(/^sku:\s*.+/));
    } catch (e) {
      // If can't parse, let server validate
    }

    if (!hasSku) {
      alert(
        "SKU is required to publish this product. Please add a SKU in the metadata before publishing.",
      );
      return;
    }

    if (confirm("Publish this product? It will be visible on your store.")) {
      const productId = event.currentTarget.dataset.editorProductId;
      const form = document.createElement("form");
      form.method = "POST";
      form.action = `/admin/products/${productId}/publish`;

      const csrfToken = document.querySelector('[name="csrf-token"]').content;
      const csrfInput = document.createElement("input");
      csrfInput.type = "hidden";
      csrfInput.name = "authenticity_token";
      csrfInput.value = csrfToken;

      const methodInput = document.createElement("input");
      methodInput.type = "hidden";
      methodInput.name = "_method";
      methodInput.value = "PATCH";

      form.appendChild(csrfInput);
      form.appendChild(methodInput);
      document.body.appendChild(form);
      form.submit();
    }
  }

  confirmProductUnpublish(event) {
    event.preventDefault();

    if (
      confirm(
        "Unpublish this product? It will no longer be visible on your store.",
      )
    ) {
      const productId = event.currentTarget.dataset.editorProductId;
      const form = document.createElement("form");
      form.method = "POST";
      form.action = `/admin/products/${productId}/unpublish`;

      const csrfToken = document.querySelector('[name="csrf-token"]').content;
      const csrfInput = document.createElement("input");
      csrfInput.type = "hidden";
      csrfInput.name = "authenticity_token";
      csrfInput.value = csrfToken;

      const methodInput = document.createElement("input");
      methodInput.type = "hidden";
      methodInput.name = "_method";
      methodInput.value = "PATCH";

      form.appendChild(csrfInput);
      form.appendChild(methodInput);
      document.body.appendChild(form);
      form.submit();
    }
  }
}

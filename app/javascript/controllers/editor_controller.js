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

      const state = {
        elementId: element.id,
        cursorPosition: element.selectionStart || 0,
        scrollPosition: element.scrollTop || 0,
        url: window.location.pathname,
      };

      sessionStorage.setItem(
        `editorState:${window.location.pathname}`,
        JSON.stringify(state),
      );

    },

    restore(textareaId) {
      const stateKey = `editorState:${window.location.pathname}`;
      const savedState = sessionStorage.getItem(stateKey);

      if (!savedState) {
        return;
      }

      const state = JSON.parse(savedState);

      const elementToRestore = state.elementId
        ? document.getElementById(state.elementId)
        : document.getElementById(textareaId);

      if (!elementToRestore) {
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
          elementToRestore.setSelectionRange(
            state.cursorPosition,
            state.cursorPosition,
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
    "mediaMenuDropdown",
    "mediaPickerModal",
    "mediaPickerContent",
    "tocPanel",
    "tocContent",
    "tocArrow",
    "saveDot",
    "saveMessage",
    "leaveModal",
    "unpublishModal",
  ];

  static values = {
    resourceType: String,
    resourceId: String,
    previewPath: String,
    collectionTemplate: String,
    asideTemplate: String,
    postLinkTemplate: String,
    pullquoteTemplate: String,
    productTemplate: String,
    currencySymbol: String,
    knownFields: Array,
    defaultAuthor: String,
    highlightMedia: String,
  };

  connect() {

    // Leave-guard modal state (see handleTurboBeforeVisit).
    this.confirmedLeave = false;
    this.pendingVisitUrl = null;

    // Unpublish-confirm modal state (see confirmUnpublish).
    this.confirmedUnpublish = false;
    this.pendingUnpublishForm = null;
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
    });

    this.textareaTarget.addEventListener("input", () => {
      this.lastCursorPosition = null;
    });

    // Live preview auto-refresh. Once the preview tab has been opened, edits
    // are pushed to it — debounced — so it updates its <main> in place without
    // a reload (scroll position preserved). See preview(), pushPreviewUpdate(),
    // and the @preview_mode receiver in layouts/site.html.erb.
    // "Opened" survives the post-save reload so edits stay live afterwards.
    this.previewStateKey = `roe-preview-open-${this.resourceTypeValue}-${this.resourceIdValue}`;
    this.previewOpened = sessionStorage.getItem(this.previewStateKey) === "1";
    this.previewUpdateTimer = null;

    // Whether a save happened immediately before this (full-reload) load. save()
    // sets this marker and we consume it here so the indicator can distinguish a
    // just-saved page ("changes saved") from a plain load (pristine, blank).
    // Cleared on read, so leaving and re-entering the editor shows pristine.
    this.savedKey = `roe-just-saved-${this.resourceTypeValue}-${this.resourceIdValue}`;
    this.savedThisSession = sessionStorage.getItem(this.savedKey) === "1";
    sessionStorage.removeItem(this.savedKey);
    this.textareaTarget.addEventListener("input", () => {
      this.updateSaveState();
      this.schedulePreviewUpdate();
    });
    this.metadataPreviewHandler = () => {
      this.updateSaveState();
      this.schedulePreviewUpdate();
    };
    document.addEventListener("metadata:changed", this.metadataPreviewHandler);

    // Keep the caret in view. The textarea grows to fit its content (no inner
    // scroll), so when the caret moves out of frame the *window* must scroll to
    // it. Throttled to one measure per frame, and it runs after the input
    // handlers above (so it sees the post-autoExpand height).
    this.caretScrollScheduled = false;
    this.caretScrollHandler = () => {
      if (this.caretScrollScheduled) return;
      this.caretScrollScheduled = true;
      requestAnimationFrame(() => {
        this.caretScrollScheduled = false;
        this.scrollCaretIntoView();
      });
    };
    this.textareaTarget.addEventListener("input", this.caretScrollHandler);
    this.textareaTarget.addEventListener("keyup", this.caretScrollHandler);
    this.textareaTarget.addEventListener("click", this.caretScrollHandler);

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

    // Listen for media picker insert events
    this.mediaPickerInsertHandler = this.handleMediaPickerInsert.bind(this);
    this.element.addEventListener(
      "media-picker:insert",
      this.mediaPickerInsertHandler,
    );

    // The gallery builder asks for images; the editor owns the modal, so it
    // does the opening. The selection comes back as media-picker:insert-gallery,
    // which the gallery builder listens for itself.
    this.galleryPickHandler = () => this.openMediaPickerFor("images", "gallery");
    this.element.addEventListener(
      "gallery-builder:pick-images",
      this.galleryPickHandler,
    );

    // Listen for media picker close events (e.g. Cancel button)
    this.mediaPickerCloseHandler = this.closeMediaPicker.bind(this);
    this.element.addEventListener(
      "media-picker:close",
      this.mediaPickerCloseHandler,
    );

    // Listen for status-change-triggered publish requests from the
    // metadata editor. Opens the publish modal — the actual save runs
    // through completePublish() once the user confirms.
    this.publishRequestHandler = () => this.showPublishModal();
    document.addEventListener(
      "metadata-editor:publish-requested",
      this.publishRequestHandler,
    );

    // The SKU generator writes to the metadata editor then fires this so the
    // publish modal (if open) rebuilds from the updated editor state.
    this.publishRefreshHandler = () => this.refreshPublishModal();
    document.addEventListener(
      "publish-modal:refresh",
      this.publishRefreshHandler,
    );

    // Just saved (server redirected back with this marker): if a preview tab is
    // live, push the freshly-saved content into it in place.
    const savedTrigger = document.querySelector('[data-trigger="refresh"]');
    if (savedTrigger && this.previewOpened) {
      this.pushPreviewUpdate();
    }

    // Prevent scroll restoration
    if ("scrollRestoration" in history) {
      history.scrollRestoration = "manual";
    }

    // Combined Enter key handler for lists, blockquotes, and footnotes
    this.enterHandler = (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        // Try list handling first (more common)
        if (this.handleListEnter(e)) return;
        // Then blockquotes (must run before footnote continuation so
        // indented `> ` lines inside footnotes continue as blockquotes)
        if (this.handleBlockquoteEnter(e)) return;
        // Then try footnote handling
        if (this.handleFootnoteEnter(e)) return;
      }
    };
    this.textareaTarget.addEventListener("keydown", this.enterHandler);

    // Add Turbo navigation warning (in-app link clicks)
    this.turboBeforeVisitHandler = this.handleTurboBeforeVisit.bind(this);
    document.addEventListener(
      "turbo:before-visit",
      this.turboBeforeVisitHandler,
    );

    // Re-arm the guard if a save submission fails/errors (no reconnect happens
    // in that case). See handleSubmitEnd.
    this.submitEndHandler = this.handleSubmitEnd.bind(this);
    document.addEventListener("turbo:submit-end", this.submitEndHandler);

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

    // Paint the save-state indicator now that baselines + savedThisSession are
    // set (shows "changes saved" after a save-reload, otherwise pristine/dirty).
    this.updateSaveState();

    // CHECK BUTTON ON INITIAL LOAD
    this.checkInitialButtonState();

    // Add global keyboard shortcut handler
    this.globalKeydownHandler = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.globalKeydownHandler);

    // Save/restore cursor state on tab switch — registered here for all content
    // types (was previously a per-view data-action on pages only, which also
    // double-bound keydown and broke Cmd/Ctrl+S there).
    this.visibilityChangeHandler = this.handleVisibilityChange.bind(this);
    document.addEventListener("visibilitychange", this.visibilityChangeHandler);

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

    // Remove global keyboard handler
    document.removeEventListener("keydown", this.globalKeydownHandler);
    document.removeEventListener(
      "visibilitychange",
      this.visibilityChangeHandler,
    );

    // Clean up event listeners
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    if (this.publishRequestHandler) {
      document.removeEventListener(
        "metadata-editor:publish-requested",
        this.publishRequestHandler,
      );
    }
    if (this.publishRefreshHandler) {
      document.removeEventListener(
        "publish-modal:refresh",
        this.publishRefreshHandler,
      );
    }
    if (this.metadataPreviewHandler) {
      document.removeEventListener(
        "metadata:changed",
        this.metadataPreviewHandler,
      );
    }
    clearTimeout(this.previewUpdateTimer);

    // Close broadcast channel
    if (this.previewChannel) {
      this.previewChannel.close();
    }

    // Remove Turbo handler
    document.removeEventListener(
      "turbo:before-visit",
      this.turboBeforeVisitHandler,
    );

    // Remove save-heal handler
    document.removeEventListener("turbo:submit-end", this.submitEndHandler);

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

    // Remove caret-into-view handlers + the mirror div
    if (this.caretScrollHandler) {
      this.textareaTarget.removeEventListener("input", this.caretScrollHandler);
      this.textareaTarget.removeEventListener("keyup", this.caretScrollHandler);
      this.textareaTarget.removeEventListener("click", this.caretScrollHandler);
    }
    if (this.caretMirror) {
      this.caretMirror.remove();
      this.caretMirror = null;
    }

    // Remove footnote done button if it exists
    this.removeFootnoteDoneButton();

    document.removeEventListener("click", this.cardMenuClickHandler);
    document.removeEventListener("keydown", this.cardMenuKeyHandler);

    // Remove media picker insert handler
    if (this.mediaPickerInsertHandler) {
      this.element.removeEventListener(
        "media-picker:insert",
        this.mediaPickerInsertHandler,
      );
    }

    if (this.galleryPickHandler) {
      this.element.removeEventListener(
        "gallery-builder:pick-images",
        this.galleryPickHandler,
      );
    }

    // Remove media picker close handler
    if (this.mediaPickerCloseHandler) {
      this.element.removeEventListener(
        "media-picker:close",
        this.mediaPickerCloseHandler,
      );
    }
  }

  // Single source of truth for "are there unsaved changes?". Compares both the
  // content and the metadata against the baselines captured in connect() (and
  // reset on save). A save in flight is never dirty.
  isDirty() {
    if (this.isSaving) return false;

    const currentContent = this.textareaTarget.value;
    const currentMetadata = this.hasMetadataTarget
      ? this.metadataTarget.value
      : "";

    return (
      currentContent !== this.originalContent ||
      currentMetadata !== this.originalMetadata
    );
  }

  // Reflect editor state in the save-state indicator, three ways:
  //   dirty              → amber dot, "unsaved changes"
  //   clean, just saved  → green dot, "changes saved"  (persists across the
  //                        save-reload via savedThisSession)
  //   clean, pristine    → green dot, no text  (as it was when loaded)
  updateSaveState() {
    if (!this.saveDotTargets.length) return;

    const dirty = this.isDirty();
    this.saveDotTargets.forEach((dot) => {
      dot.classList.toggle("bg-amber-500", dirty);
      dot.classList.toggle("bg-green-500", !dirty);
    });

    // pristine (blank) vs just-saved vs dirty — mirrored to every instance
    // (top row + drawer).
    const message = dirty
      ? "unsaved changes"
      : this.savedThisSession
        ? "changes saved"
        : "";
    this.saveMessageTargets.forEach((el) => {
      el.textContent = message;
    });
  }

  // Scroll the window so the caret is visible when it moves out of frame.
  // Only scrolls when the caret is above the (sticky-toolbar-aware) top edge or
  // below the bottom edge — an in-view caret never moves the page. Instant, no
  // animation.
  scrollCaretIntoView() {
    const ta = this.textareaTarget;
    if (document.activeElement !== ta) return;

    const caret = this.caretCoordinates();
    const taRect = ta.getBoundingClientRect();
    const caretTop = taRect.top + caret.top - ta.scrollTop;
    const caretBottom = caretTop + caret.height;

    // Top edge clears the sticky toolbar while it's pinned to the top.
    let topEdge = 24;
    const toolbar = this.element.querySelector(
      '[data-controller~="sticky-toolbar"]',
    );
    if (toolbar) {
      const tb = toolbar.getBoundingClientRect();
      if (tb.top <= 0) topEdge = tb.bottom + 8;
    }
    const bottomEdge = window.innerHeight - 60;

    if (caretBottom > bottomEdge) {
      window.scrollBy({ top: caretBottom - bottomEdge, behavior: "instant" });
    } else if (caretTop < topEdge) {
      window.scrollBy({ top: caretTop - topEdge, behavior: "instant" });
    }
  }

  // Caret position within the textarea's border box, via a hidden mirror div
  // that replicates the textarea's text layout (font, width, padding, wrapping)
  // up to the caret. Returns { top, height } in pixels. Standard technique —
  // textareas expose no caret geometry directly.
  caretCoordinates() {
    const ta = this.textareaTarget;
    const pos = ta.selectionStart;
    const computed = window.getComputedStyle(ta);

    if (!this.caretMirror) {
      this.caretMirror = document.createElement("div");
      this.caretMirror.setAttribute("aria-hidden", "true");
      document.body.appendChild(this.caretMirror);
    }
    const div = this.caretMirror;
    const style = div.style;
    style.position = "absolute";
    style.top = "0";
    style.left = "-9999px";
    style.visibility = "hidden";
    style.whiteSpace = "pre-wrap";
    style.overflowWrap = "break-word";

    [
      "boxSizing",
      "width",
      "borderTopWidth",
      "borderRightWidth",
      "borderBottomWidth",
      "borderLeftWidth",
      "paddingTop",
      "paddingRight",
      "paddingBottom",
      "paddingLeft",
      "fontStyle",
      "fontVariant",
      "fontWeight",
      "fontStretch",
      "fontSize",
      "lineHeight",
      "fontFamily",
      "textAlign",
      "textTransform",
      "textIndent",
      "letterSpacing",
      "wordSpacing",
      "tabSize",
    ].forEach((prop) => {
      style[prop] = computed[prop];
    });

    // A run of spaces right before the caret hangs/collapses at a line edge in
    // pre-wrap, so a just-typed trailing space wouldn't advance the measured
    // caret. Swap that trailing run for non-breaking spaces (same width, no
    // collapse) so the caret advances/wraps like it does in the real textarea.
    // Only the trailing run is touched, so wrapping of the rest is unaffected.
    const before = ta.value
      .substring(0, pos)
      .replace(/ +$/, (run) => "\u00a0".repeat(run.length));
    div.textContent = before;
    const marker = document.createElement("span");
    // Non-empty so the marker has a box even at a line start / end of text.
    marker.textContent = ta.value.substring(pos) || ".";
    div.appendChild(marker);

    const top = marker.offsetTop + parseInt(computed.borderTopWidth, 10);
    const height = parseInt(computed.lineHeight, 10) || marker.offsetHeight;
    return { top, height };
  }

  // Fallback native prompt for pages that don't render the styled leave modal
  // (e.g. content types not yet migrated). Returns true if the user chose to
  // leave.
  askLeave() {
    return window.confirm(
      "You have unsaved changes. Are you sure you want to leave?",
    );
  }

  // In-app navigation (link clicks / "Back to Posts"). Note: the browser
  // Back/Forward button does NOT fire turbo:before-visit — that path stays
  // guarded by the native beforeunload prompt (browsers won't allow a custom
  // modal for a real unload).
  handleTurboBeforeVisit(event) {
    if (this.confirmedLeave) return; // user already chose to leave; let it go
    if (!this.isDirty()) return;

    // No styled modal on this page: fall back to the native confirm.
    if (!this.hasLeaveModalTarget) {
      if (!this.askLeave()) {
        event.preventDefault();
        this.restoreEditorFocus();
      }
      return;
    }

    // Stop the visit and ask via the modal; resumed in confirmLeaveNavigation.
    event.preventDefault();
    this.pendingVisitUrl = event.detail.url;
    this.leaveModalTarget.classList.remove("hidden");
  }

  // "Leave without saving" — resume the pending navigation. confirmedLeave lets
  // the re-issued visit pass the guard above.
  confirmLeaveNavigation() {
    this.confirmedLeave = true;
    if (this.hasLeaveModalTarget) {
      this.leaveModalTarget.classList.add("hidden");
    }

    // The user chose to leave via the modal, so drop the native beforeunload
    // guard — otherwise a full navigation (or the location.href fallback) would
    // pop the browser's prompt on top of our modal.
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    if (this.pendingVisitUrl && window.Turbo) {
      window.Turbo.visit(this.pendingVisitUrl);
    } else if (this.pendingVisitUrl) {
      window.location.href = this.pendingVisitUrl;
    }
  }

  // "Stay" — dismiss the modal and return focus to the editor.
  cancelLeaveNavigation() {
    if (this.hasLeaveModalTarget) {
      this.leaveModalTarget.classList.add("hidden");
    }
    this.pendingVisitUrl = null;
    this.restoreEditorFocus();
  }

  // Clicking the dimmed backdrop (but not the dialog card) is treated as "Stay".
  leaveModalBackdrop(event) {
    if (event.target === this.leaveModalTarget) this.cancelLeaveNavigation();
  }

  restoreEditorFocus() {
    const elementToFocus = this.lastFocusedInput || this.textareaTarget;
    const cursorPosition = elementToFocus.selectionStart || 0;

    requestAnimationFrame(() => {
      elementToFocus.focus({ preventScroll: true });
      if (elementToFocus.selectionStart !== undefined) {
        elementToFocus.setSelectionRange(cursorPosition, cursorPosition);
      }
    });
  }

  // Self-heal the saving flag. save()/publish/unpublish set isSaving=true and
  // drop the beforeunload guard; a successful save redirects and reconnects
  // (resetting everything). But if the submission FAILS or errors, no reconnect
  // happens — without this the guard would stay disabled until a manual reload.
  handleSubmitEnd(event) {
    if (event.detail && event.detail.success) return;
    this.isSaving = false;
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    window.addEventListener("beforeunload", this.beforeUnloadHandler);
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
    // Parse status from YAML. Treat a missing status field as 'draft' —
    // consistent with the Ruby default, and ensures the Publish button
    // is shown for content that has no status set yet.
    const statusMatch = yaml.match(/^status:\s*["']?(\w+)["']?$/m);
    const newStatus = statusMatch ? statusMatch[1] : "draft";

    // Publish button is shown when the post isn't fully published yet — that
    // includes both 'draft' and 'unlisted'. Unpublish only makes sense once the
    // post is actually 'published'.
    const shouldShowPublish = newStatus !== "published";

    // There can be more than one container now (top row + bottom drawer), so
    // update them all. Read current state + the post id from whichever button
    // is currently rendered.
    const containers = this.element.querySelectorAll(
      ".publish-button-container",
    );
    if (!containers.length) return;

    const publishButton = this.element.querySelector(
      '[data-action*="confirmPublish"]',
    );
    const unpublishButton = this.element.querySelector(
      '[data-action*="confirmUnpublish"]',
    );

    const currentlyShowingPublish = publishButton !== null;
    if (currentlyShowingPublish === shouldShowPublish) return; // no change

    const postId =
      publishButton?.dataset.editorPostId || this.resourceIdValue;
    if (!postId) return;

    // Type-generic base path: post -> /admin/posts, page -> /admin/pages, etc.
    const basePath = `/admin/${this.resourceTypeValue}s`;

    const authToken =
      document.querySelector('meta[name="csrf-token"]')?.content || "";

    const html = shouldShowPublish
      ? // Publish — opens the publish modal; the save happens via the main
        // form when the user confirms.
        `<button type="button"
                data-action="click->editor#confirmPublish"
                data-editor-post-id="${postId}"
                class="uppercase text-xs px-1.5 py-0 border border-slate-800 bg-slate-200 hover:bg-slate-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
          Publish
        </button>`
      : `<form action="${basePath}/${postId}/unpublish"
              method="post"
              data-turbo="false"
              data-action="submit->editor#confirmUnpublish">
          <input type="hidden" name="_method" value="patch">
          <input type="hidden" name="authenticity_token" value="${authToken}">
          <button type="submit"
                  class="uppercase text-xs text-white px-1.5 py-0 border border-slate-800 bg-slate-400 hover:bg-slate-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Unpublish
          </button>
        </form>`;

    containers.forEach((container) => {
      container.innerHTML = html;
    });
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

  insertMark(event) {
    event.preventDefault();
    this.wrapSelectionWithSavedPosition(
      "<mark>",
      "</mark>",
      "highlighted text",
    );
  }

  insertFootnote(event) {
    event.preventDefault();

    const content = this.textareaTarget.value;
    const footnoteMatches = [...content.matchAll(/\[\^(\d+)\]/g)];
    const footnoteNumbers = footnoteMatches.map((m) => parseInt(m[1]));
    const nextNumber =
      footnoteNumbers.length > 0 ? Math.max(...footnoteNumbers) + 1 : 1;

    const originalPos = this.textareaTarget.selectionStart;

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

    // State for cleanup if the user dismisses without typing. Positions
    // are valid as long as the inline anchor area stays intact — the
    // returnFromFootnote() cleanup re-verifies before mutating anything.
    this.pendingFootnote = {
      number: nextNumber,
      inlineRefStart: originalPos,
      inlineRefEnd: positionAfterReference,
      footnoteBlockStart: endPos,
      footnoteContentStart: cursorPos,
    };

    this.showFootnoteDoneButton(positionAfterReference);

    // Defer the window scroll: the two execCommand calls above fired
    // input events that schedule rAF callbacks comparing against the
    // OLD scrollBeforeInput. If we scroll now, those rAFs will fire
    // and snap us back. setTimeout(60) lets them settle first, then
    // scrollCursorIntoView() updates the lock baseline so subsequent
    // typing into the footnote doesn't snap back to the top either.
    setTimeout(() => {
      this.autoExpandTextarea();
      this.scrollCursorIntoView(this.textareaTarget.value.length);
    }, 60);
  }

  // Scroll the WINDOW (not the textarea) so the cursor at `position`
  // sits about 1/3 down the viewport. The textarea auto-expands to
  // fit its content, so it has no internal scrollbar — adjusting
  // textarea.scrollTop is a no-op. We have to translate the cursor's
  // position-in-text to a pixel y-coordinate in the document and
  // scroll the window there.
  scrollCursorIntoView(position) {
    const textarea = this.textareaTarget;
    const style = window.getComputedStyle(textarea);
    const lineHeight =
      parseInt(style.lineHeight) || parseInt(style.fontSize) * 1.5;
    const paddingTop = parseInt(style.paddingTop) || 0;

    const linesBefore = textarea.value
      .substring(0, position)
      .split("\n").length;
    const cursorY = paddingTop + (linesBefore - 1) * lineHeight;

    const textareaRect = textarea.getBoundingClientRect();
    const cursorDocumentY = window.scrollY + textareaRect.top + cursorY;

    const targetScroll = Math.max(0, cursorDocumentY - window.innerHeight / 3);

    window.scrollTo({ top: targetScroll, behavior: "instant" });

    // Reset the input-lock baseline to where we just landed so the
    // next input event doesn't snap the page back.
    this.scrollBeforeInput = window.scrollY;
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

      const currentLine = lines[currentLineNumber];
      // Continue a blockquote inside the footnote. The blockquote handler
      // catches regular `    > ` continuation lines; this covers the
      // footnote definition line (`[^N]: > ...`) and acts as a fallback.
      const isBlockquoteLine =
        currentLine.match(/^(\s*)>(?:\s|$)/) ||
        (currentLine === footnoteDefLine &&
          footnoteDefLine.match(/^\[\^\d+\]:\s*(>)(?:\s|$)/));

      if (isBlockquoteLine) {
        document.execCommand("insertText", false, "\n" + indent + "> ");
      } else {
        document.execCommand("insertText", false, "\n" + indent);
      }
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
      "fixed bottom-8 right-12 z-50 uppercase text-base px-1.5 py-2 border border-gray-800 bg-blue-200 hover:bg-blue-300 font-mono rounded-xs";
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

    let targetPosition = returnPosition;
    const pending = this.pendingFootnote;

    // Cleanup pass: if the user pressed Done / Esc without adding any
    // footnote text, remove the empty footnote definition AND the
    // inline anchor so they're not left with a dangling reference.
    //
    // Two safety checks before mutating:
    //   1. inline anchor at recorded position still reads as the
    //      `[^N]` we inserted (positions could have shifted if the
    //      user edited text BEFORE the anchor while the prompt was
    //      open — rare but possible).
    //   2. text after the footnote `[^N]: ` is whitespace-only.
    if (pending) {
      const content = this.textareaTarget.value;
      const expectedRef = `[^${pending.number}]`;
      const actualRef = content.substring(
        pending.inlineRefStart,
        pending.inlineRefEnd,
      );
      const inlineRefIntact = actualRef === expectedRef;
      const footnoteEmpty =
        content.substring(pending.footnoteContentStart).trim() === "";

      if (inlineRefIntact && footnoteEmpty) {
        this.textareaTarget.focus({ preventScroll: true });

        // Remove the footnote block (separator + `[^N]: `). We delete
        // from footnoteBlockStart to current end of content, which is
        // safe because the user didn't type past that point.
        this.textareaTarget.setSelectionRange(
          pending.footnoteBlockStart,
          this.textareaTarget.value.length,
        );
        document.execCommand("insertText", false, "");

        // Remove the inline anchor. Positions are still valid: the
        // deletion above only affected content AFTER inlineRefEnd.
        this.textareaTarget.setSelectionRange(
          pending.inlineRefStart,
          pending.inlineRefEnd,
        );
        document.execCommand("insertText", false, "");

        targetPosition = pending.inlineRefStart;
      }
    }

    this.pendingFootnote = null;

    this.textareaTarget.focus({ preventScroll: true });
    this.textareaTarget.setSelectionRange(targetPosition, targetPosition);

    this.removeFootnoteDoneButton();

    // Defer scroll past the input-lock rAF cycle, same reasoning as
    // insertFootnote(). The cleanup path fires execCommand events too.
    setTimeout(() => {
      this.autoExpandTextarea();
      this.scrollCursorIntoView(targetPosition);
    }, 60);
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

  handleBlockquoteEnter(event) {
    const cursorPos = this.textareaTarget.selectionStart;
    const content = this.textareaTarget.value;
    const beforeCursor = content.substring(0, cursorPos);
    const afterCursor = content.substring(cursorPos);

    // Get current line
    const lines = beforeCursor.split("\n");
    const currentLine = lines[lines.length - 1];

    // Match a blockquote line: optional leading whitespace, >, optional space
    const blockquoteMatch = currentLine.match(/^(\s*)>\s?(.*)$/);
    if (!blockquoteMatch) return false;

    // Only handle Enter at end of line
    const nextChar = afterCursor[0];
    const atEndOfLine = !nextChar || nextChar === "\n";
    if (!atEndOfLine) return false;

    const leadingSpace = blockquoteMatch[1];
    const lineContent = blockquoteMatch[2];
    const isEmpty = lineContent.trim() === "";

    if (isEmpty) {
      const previousLine = lines.length > 1 ? lines[lines.length - 2] : null;
      const previousIsEmptyBlockquote =
        previousLine && previousLine.match(/^(\s*)>\s*$/);

      if (previousIsEmptyBlockquote) {
        event.preventDefault();
        // Exit the blockquote: remove the current empty `>` line AND the
        // previous empty `>` separator line, then land on a new empty line
        // preserving any leading indentation (so footnotes keep their indent).
        const currentLineStart = beforeCursor.length - currentLine.length;
        const previousLineStart =
          currentLineStart - previousLine.length - 1;
        this.textareaTarget.value =
          content.substring(0, previousLineStart) +
          "\n" +
          leadingSpace +
          afterCursor;
        this.textareaTarget.selectionStart = this.textareaTarget.selectionEnd =
          previousLineStart + 1 + leadingSpace.length;
        return true;
      }
    }

    // Continue the blockquote on a new line
    event.preventDefault();
    document.execCommand(
      "insertText",
      false,
      "\n" + leadingSpace + "> ",
    );
    return true;
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

  // ========== PRODUCT ACTIONS ==========

  showProductPrompt(event) {
    event.preventDefault();

    // Save cursor position FIRST (for both paths)
    this.savedCursorBeforeModal = this.textareaTarget.selectionStart;

    // Check if we're on a product page
    const resourceType = this.resourceTypeValue;
    const resourceId = this.resourceIdValue;

    if (resourceType === "product" && resourceId) {
      // On product page - insert immediately
      fetch(`/admin/products/${resourceId}.json`)
        .then((response) => response.json())
        .then((product) => this.insertProductTemplate(product))
        .catch((error) => console.error("Error fetching product:", error));
      return;
    }

    // Not on product page - show search modal
    this.savedCursorBeforeModal = this.textareaTarget.selectionStart;

    const overlay = document.createElement("div");
    overlay.id = "product-modal";
    overlay.className = "fixed inset-0 flex items-center justify-center z-50";
    overlay.style.cssText = "background-color: rgba(0, 0, 0, 0.2);";
    overlay.innerHTML = `
      <div class="bg-white p-6 w-96 border border-gray-400">
        <h3 class="text-lg font-bold mb-4">Insert Product</h3>
        <div class="relative mb-4">
          <input
            type="text"
            id="product-search-input"
            placeholder="Search for a product..."
            class="w-full px-3 py-2 border border-gray-300"
            autocomplete="off"
          >
          <div id="product-search-results" class="hidden absolute top-full left-0 right-0 mt-1 bg-white border border-gray-300 max-h-60 overflow-y-auto z-10"></div>
        </div>
        <div class="flex justify-end gap-2">
          <button type="button"
                  id="product-cancel"
                  class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">
            Cancel
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    const input = document.getElementById("product-search-input");
    const resultsDiv = document.getElementById("product-search-results");
    const cancelButton = document.getElementById("product-cancel");

    input.focus();

    cancelButton.addEventListener("click", () => {
      this.closeProductModal();
    });

    let searchTimeout;
    let selectedIndex = -1;

    // Handle product selection - use event delegation
    resultsDiv.addEventListener("click", (e) => {
      const button = e.target.closest("button[data-product]");
      if (button) {
        e.preventDefault();
        const productData = JSON.parse(button.dataset.product);
        this.insertProductTemplate(productData);
      }
    });

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
        this.closeProductModal();
      }
    });

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
      selectedIndex = -1;
      const query = e.target.value.trim();

      if (query.length < 2) {
        resultsDiv.classList.add("hidden");
        return;
      }

      searchTimeout = setTimeout(() => this.searchProducts(query), 300);
    });

    overlay.addEventListener("click", (e) => {
      if (e.target.id === "product-modal") {
        this.closeProductModal();
      }
    });
  }

  searchProducts(query) {
    const resultsDiv = document.getElementById("product-search-results");

    fetch(`/admin/products/search?query=${encodeURIComponent(query)}`)
      .then((response) => response.json())
      .then((products) => {
        if (products.length === 0) {
          resultsDiv.innerHTML =
            '<div class="p-2 text-sm text-gray-500">No products found</div>';
          resultsDiv.classList.remove("hidden");
          return;
        }

        resultsDiv.innerHTML = products
          .map(
            (product) => `
          <button type="button"
                  data-product='${JSON.stringify(product).replace(/'/g, "&apos;")}'
                  class="w-full text-left px-3 py-2 hover:bg-gray-100 border-b border-gray-200 last:border-b-0">
            <div class="font-medium text-sm">${this.escapeHtml(product.title)}</div>
            <div class="text-xs text-gray-600">${this.escapeHtml(product.sku)} - £${product.price}</div>
          </button>
        `,
          )
          .join("");

        resultsDiv.classList.remove("hidden");
      })
      .catch((error) => {
        console.error("Product search error:", error);
        resultsDiv.innerHTML =
          '<div class="p-2 text-sm text-red-500">Search failed</div>';
        resultsDiv.classList.remove("hidden");
      });
  }

  insertProductTemplate(product) {

    // Get template and currency symbol
    const template = this.productTemplateValue || "";
    const currencySymbol = this.getCurrencySymbol();

    // Use fallback for empty description
    const description =
      product.description && product.description.trim()
        ? product.description
        : "Product description";

    // Replace placeholders
    let finalTemplate = template
      .replace(/@image/g, product.image || "")
      .replace(/@title/g, product.title || "")
      .replace(/@price/g, currencySymbol + (product.price || "0.00"))
      .replace(/@description/g, description)
      .replace(/@sku/g, product.sku || "");

    // Clean up extra blank lines (reduce 3+ newlines to 2)
    finalTemplate = finalTemplate.replace(/\n{3,}/g, "\n\n");

    // Focus textarea
    this.textareaTarget.focus({ preventScroll: true });

    // Restore saved cursor position
    if (
      this.savedCursorBeforeModal !== null &&
      this.savedCursorBeforeModal !== undefined
    ) {
      this.textareaTarget.setSelectionRange(
        this.savedCursorBeforeModal,
        this.savedCursorBeforeModal,
      );
    }

    // Insert template
    document.execCommand("insertText", false, finalTemplate);

    // Clear saved position
    this.savedCursorBeforeModal = null;

    this.closeProductModal();

  }

  closeProductModal() {
    const modal = document.getElementById("product-modal");
    if (modal) {
      modal.remove();
    }

    if (this.hasTextareaTarget) {
      this.textareaTarget.focus({ preventScroll: true });
    }
  }

  getCurrencySymbol() {
    // Use Stimulus value accessor
    return this.hasCurrencySymbolValue ? this.currencySymbolValue : "$";
  }

  // ========== MEDIA ACTIONS ==========

  toggleMediaMenu(event) {
    event.preventDefault();
    event.stopPropagation();
    const dropdown = this.mediaMenuDropdownTarget;
    const isHidden = dropdown.classList.contains("hidden");

    // Close card menu if open
    if (this.hasCardMenuTarget) {
      this.cardMenuTarget.classList.add("hidden");
    }

    if (isHidden) {
      dropdown.classList.remove("hidden");
      // Save cursor position now, before focus moves away
      this.savedMediaPosition = this.textareaTarget.selectionStart;
      // Close on outside click
      this._closeMediaMenuHandler = (e) => {
        if (
          !dropdown.contains(e.target) &&
          !e.target.closest('[data-action*="toggleMediaMenu"]')
        ) {
          dropdown.classList.add("hidden");
          document.removeEventListener("click", this._closeMediaMenuHandler);
        }
      };
      setTimeout(
        () => document.addEventListener("click", this._closeMediaMenuHandler),
        0,
      );
    } else {
      dropdown.classList.add("hidden");
    }
  }

  openMediaPicker(event) {
    event.preventDefault();
    this.openMediaPickerFor(event.currentTarget.dataset.mediaType || "images");
  }

  // Split out so the gallery builder can open the picker without duplicating
  // the modal handling or the fetch. `openedFor` travels to the server, which
  // decides what the toolbar's primary button says and does — one definition of
  // that label rather than a client-side patch after load.
  openMediaPickerFor(mediaType, openedFor = null) {
    // Close dropdown
    if (this.hasMediaMenuDropdownTarget) {
      this.mediaMenuDropdownTarget.classList.add("hidden");
    }

    // Save cursor position (use savedMediaPosition if set by toggleMediaMenu)
    if (this.savedMediaPosition == null) {
      this.savedMediaPosition = this.textareaTarget.selectionStart;
    }

    // Show modal
    this.mediaPickerModalTarget.style.display = "flex";
    document.body.style.overflow = "hidden";

    // Load picker content via fetch
    this.mediaPickerContentTarget.innerHTML =
      '<div class="flex items-center justify-center h-full text-gray-400 font-mono text-sm">Loading...</div>';

    const params = new URLSearchParams({ media_type: mediaType });
    if (openedFor) params.set("for", openedFor);

    fetch(`/admin/medium/picker?${params}`, {
      headers: { "X-Requested-With": "XMLHttpRequest" },
    })
      .then((r) => r.text())
      .then((html) => {
        this.mediaPickerContentTarget.innerHTML = html;
      })
      .catch(() => {
        this.mediaPickerContentTarget.innerHTML =
          '<p class="p-4 text-red-600 font-mono text-sm">Failed to load media.</p>';
      });
  }

  closeMediaPicker(event) {
    // Prevent any form submission that might be triggered
    if (event && event.preventDefault) event.preventDefault();
    this.mediaPickerModalTarget.style.display = "none";
    document.body.style.overflow = "";
    this.savedMediaPosition = null;
  }

  closeMediaPickerOnBackdrop(event) {
    // Only close if clicking the backdrop itself (not the modal content)
    if (event.target === this.mediaPickerModalTarget) {
      event.preventDefault();
      this.closeMediaPicker();
    }
  }

  stopModalClose(event) {
    event.stopPropagation();
  }

  handleMediaPickerInsert(event) {
    const { mediaItems } = event.detail;
    if (!mediaItems || mediaItems.length === 0) return;

    const position =
      this.savedMediaPosition ?? this.textareaTarget.selectionStart;

    // Build markdown for all selected items, one per line
    const markdown = mediaItems
      .map((item) => `![${item.filename}](${item.path})`)
      .join("\n");

    // Close modal first, then insert - this ensures the textarea is
    // the active element so execCommand lands in the right place and
    // the browser's undo stack is intact
    this.closeMediaPicker();

    this.textareaTarget.focus({ preventScroll: true });
    this.textareaTarget.setSelectionRange(position, position);

    // execCommand is deprecated but still the only reliable cross-browser
    // way to insert text that supports native undo (Cmd+Z)
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

  // Closes the TOC without toggling it. The markdown check shares the tab strip
  // and the panel space below it, so opening that one closes this one. Separate
  // from toggleTOC because a toggle would re-open the TOC on a second click of
  // the markdown tab, leaving both panels open — the thing the tabs prevent.
  closeTOC() {
    if (!this.hasTocPanelTarget) return;

    this.tocPanelTarget.classList.add("hidden");
    if (this.hasTocArrowTarget) this.tocArrowTarget.textContent = "▶";
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
    event?.preventDefault();
    if (!this.previewPathValue) {
      console.error("Preview path not defined");
      return;
    }

    const previewId = `${this.resourceTypeValue}-${this.resourceIdValue}`;

    // From here on, debounced edits will keep this tab live (see
    // schedulePreviewUpdate / pushPreviewUpdate). Persist so it stays live
    // across the post-save reload.
    this.previewOpened = true;
    sessionStorage.setItem(this.previewStateKey, "1");

    // POST the CURRENT (possibly unsaved) content so the preview reflects the
    // editor as it is right now, not the last-saved file. The preview endpoints
    // render params[:content] (+ params[:metadata] where applicable). Targeting
    // the named window means the first Preview opens a tab and later ones
    // refresh that same tab in the background.
    const form = document.createElement("form");
    form.method = "POST";
    form.action = this.previewPathValue;
    form.target = previewId;
    form.style.display = "none";

    const addField = (name, value) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      form.appendChild(input);
    };

    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (token) addField("authenticity_token", token);
    addField("content", this.textareaTarget.value);
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField) addField("metadata", metadataField.value);

    document.body.appendChild(form);
    form.submit();
    form.remove();
  }

  // Debounce edits before pushing to the open preview tab, so we render at most
  // once per typing pause rather than per keystroke. No-op until the preview has
  // actually been opened.
  schedulePreviewUpdate() {
    if (!this.previewOpened) return;
    clearTimeout(this.previewUpdateTimer);
    this.previewUpdateTimer = setTimeout(() => this.pushPreviewUpdate(), 800);
  }

  // Push to the preview tab NOW, skipping the typing debounce. For a change the
  // writer made in one click — Fix All, Undo Fix — there is no typing pause to
  // wait at the end of, and 800ms of an unchanged preview reads as the click
  // having done nothing. Clearing the timer first means the `input` event that
  // accompanied the change doesn't fire a second, redundant render.
  refreshPreview() {
    if (!this.previewOpened) return;

    clearTimeout(this.previewUpdateTimer);
    this.pushPreviewUpdate();
  }

  // Render the current (unsaved) content server-side and hand the resulting
  // <main> HTML to the preview tab over the BroadcastChannel. The receiver swaps
  // it in place, preserving scroll — no reload. Fire-and-forget; failures are
  // silent (the tab may simply be closed).
  pushPreviewUpdate() {
    if (!this.previewPathValue || !this.previewChannel) return;

    const body = new FormData();
    body.append("content", this.textareaTarget.value);
    const metadataField = this.element.querySelector('[name="metadata"]');
    if (metadataField) body.append("metadata", metadataField.value);

    const token = document.querySelector('meta[name="csrf-token"]')?.content;

    fetch(this.previewPathValue, {
      method: "POST",
      headers: { "X-CSRF-Token": token || "" },
      body,
    })
      .then((response) => (response.ok ? response.text() : null))
      .then((html) => {
        if (!html) return;
        const main = new DOMParser()
          .parseFromString(html, "text/html")
          .querySelector("main");
        if (main) {
          this.previewChannel.postMessage({
            action: "render",
            html: main.innerHTML,
          });
        }
      })
      .catch(() => {});
  }

  // ========== FORM ACTIONS ==========

  save(event) {

    // Mark that we're saving to skip dirty checks
    this.isSaving = true;

    // Leave a marker so the indicator shows "changes saved" after the reload
    // (dirty state still wins, so a failed save that stays dirty won't mislabel).
    sessionStorage.setItem(this.savedKey, "1");

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

    // The preview is kept current by the debounced live updates; the post-save
    // reload re-pushes the saved content (see the data-trigger="refresh" path
    // in connect). No pre-submit broadcast needed here.

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
    // Escape closes the leave-guard modal (= "Stay"), and takes priority over
    // the editor's other shortcuts while it's open.
    if (
      event.key === "Escape" &&
      this.hasLeaveModalTarget &&
      !this.leaveModalTarget.classList.contains("hidden")
    ) {
      event.preventDefault();
      this.cancelLeaveNavigation();
      return;
    }
    if (
      event.key === "Escape" &&
      this.hasUnpublishModalTarget &&
      !this.unpublishModalTarget.classList.contains("hidden")
    ) {
      event.preventDefault();
      this.cancelUnpublish();
      return;
    }
    // Escape closes the publish modal — unless the SKU generator is open on top
    // of it (that keeps its own Cancel button).
    if (
      event.key === "Escape" &&
      document.querySelector("[data-publish-modal]") &&
      !document.getElementById("sku-generator-modal")?.innerHTML.trim()
    ) {
      event.preventDefault();
      this.cancelPublish();
      return;
    }

    // Only process shortcuts when textarea has focus
    const isTextareaFocused = document.activeElement === this.textareaTarget;

    // Cmd/Ctrl+S to save
    if ((event.metaKey || event.ctrlKey) && event.key === "s") {
      event.preventDefault();
      // When the publish modal is open, Cmd/Ctrl+S means "Save & Publish"
      // (completePublish applies the modal's fields) — NOT the plain save,
      // which would submit without them. Skip while the SKU generator is up.
      if (
        document.querySelector("[data-publish-modal]") &&
        !document.getElementById("sku-generator-modal")?.innerHTML.trim()
      ) {
        this.completePublish();
        return;
      }
      this.formTarget.requestSubmit();
    }

    // Cmd/Ctrl+P to preview
    if ((event.metaKey || event.ctrlKey) && event.key === "p") {
      event.preventDefault();
      this.preview(event);
    }

    // Formatting shortcuts - only when textarea is focused
    if (isTextareaFocused && (event.metaKey || event.ctrlKey)) {
      switch (event.key.toLowerCase()) {
        case "b":
          event.preventDefault();
          this.insertBold(event);
          break;
        case "i":
          event.preventDefault();
          this.insertItalic(event);
          break;
        case "~":
          event.preventDefault();
          this.insertStrike(event);
          break;
        case "k":
          event.preventDefault();
          this.insertLink(event);
          break;
      }
    }
  }

  // ========== PUBLISH/UNPUBLISH CONFIRMATIONS ==========

  showPublishModal(postId) {
    const id = postId || this.resourceIdValue;
    if (!id) {
      console.error("Resource ID not found");
      return;
    }

    // Build the URL from the resource type so pages hit
    // /admin/pages/:id/publish_modal and posts hit
    // /admin/posts/:id/publish_modal.
    const resourceType = this.resourceTypeValue || "post";
    const resourcePath = `${resourceType}s`; // post -> posts, page -> pages

    // Capture the metadata-editor's current state so the modal can build
    // requirements from what's *about to be saved*, not the last-synced
    // file. This catches things like a just-changed post_type or a brand
    // new podcast post that has audio/duration fields the file doesn't
    // know about yet.
    const metadataEditorEl = this.element.querySelector(
      '[data-controller~="metadata-editor"]',
    );
    const metadataEditorCtrl = metadataEditorEl
      ? this.application.getControllerForElementAndIdentifier(
          metadataEditorEl,
          "metadata-editor",
        )
      : null;
    let currentMetadata = "";
    if (metadataEditorCtrl) {
      if (
        metadataEditorCtrl.isYamlView &&
        metadataEditorCtrl.hasYamlTextareaTarget
      ) {
        currentMetadata = metadataEditorCtrl.yamlTextareaTarget.value;
      } else {
        currentMetadata = metadataEditorCtrl.formToYaml();
      }
    }

    // Live inside the editor element so the modal's data-action="click->
    // editor#completePublish" / cancelPublish actions actually dispatch
    // on this controller (Stimulus only matches inside scope).
    let modalContainer = document.getElementById("publish-modal-container");
    if (!modalContainer) {
      modalContainer = document.createElement("div");
      modalContainer.id = "publish-modal-container";
      this.element.appendChild(modalContainer);
    } else if (!this.element.contains(modalContainer)) {
      this.element.appendChild(modalContainer);
    }

    const csrfToken =
      document.querySelector('meta[name="csrf-token"]')?.content || "";
    const formData = new FormData();
    formData.append("metadata", currentMetadata);

    fetch(`/admin/${resourcePath}/${id}/publish_modal`, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken, Accept: "text/html" },
      body: formData,
    })
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.text();
      })
      .then((html) => {
        modalContainer.innerHTML = html;
        this.setScrollLock(true);
      })
      .catch((err) => {
        console.error("Failed to load publish modal:", err);
        modalContainer.innerHTML = "";
        this.setScrollLock(false);
      });
  }

  // Write a value to the metadata editor (the source of truth). Updates the
  // existing [data-metadata-field] input, or appends a hidden one so formToYaml
  // picks it up on submit.
  applyMetadataField(name, value) {
    const metadataEditor = document.querySelector(
      '[data-controller~="metadata-editor"]',
    );
    if (!metadataEditor) return;

    const field = metadataEditor.querySelector(
      `[data-metadata-field="${name}"]`,
    );
    if (field) {
      let v = value;
      // A date-only value ("2026-07-05") into a datetime-local field is rejected
      // by the browser (the field goes blank). Give it the current time, to
      // match what the metadata editor does when you set a date there.
      if (field.type === "datetime-local" && v && !v.includes("T")) {
        const now = new Date();
        const hh = String(now.getHours()).padStart(2, "0");
        const mm = String(now.getMinutes()).padStart(2, "0");
        v = `${v}T${hh}:${mm}`;
      }
      field.value = v;
      field.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }
    const fieldsContainer = metadataEditor.querySelector(
      '[data-metadata-editor-target="fieldsContainer"]',
    );
    if (fieldsContainer) {
      const hidden = document.createElement("input");
      hidden.type = "hidden";
      hidden.dataset.metadataField = name;
      hidden.name = `metadata_fields[${name}]`;
      hidden.value = value;
      fieldsContainer.appendChild(hidden);
    }
  }

  // A publish-modal input changed — mirror it straight into the metadata editor.
  syncModalField(event) {
    const input = event.target;
    const name = this._extractMetadataFieldName(input.name);
    if (name) this.applyMetadataField(name, input.value.trim());
  }

  // Rebuild the publish modal from the metadata editor. Since the editor is the
  // source of truth, a plain rebuild is correct — no field preservation needed.
  // No-op when the modal isn't open. Fired by the SKU generator after it writes.
  refreshPublishModal() {
    const modal = document.getElementById("publish-modal-container");
    if (!modal || !modal.innerHTML.trim()) return;
    this.showPublishModal(this.resourceIdValue);
  }

  // Lock/unlock background scroll while a modal is open. Locks both <html> and
  // <body> since either can be the viewport's scroll container.
  setScrollLock(locked) {
    const value = locked ? "hidden" : "";
    document.documentElement.style.overflow = value;
    document.body.style.overflow = value;
  }

  // Triggered by the Publish button OR by the metadata-editor when the
  // user changes the status select to 'published'. Opens the modal — the
  // actual save happens in completePublish() once the user confirms.
  confirmPublish(event) {
    if (event && event.preventDefault) event.preventDefault();

    this.isSaving = true;
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);

    const postId =
      event?.currentTarget?.dataset?.editorPostId ||
      event?.target?.dataset?.editorPostId ||
      this.resourceIdValue;

    this.showPublishModal(postId);
  }

  // Modal "Save & Publish" button. Pulls the modal's collected values
  // into the main metadata editor, sets status to 'published', then
  // submits the regular Save form so content + metadata + status all
  // persist in a single round trip.
  completePublish(event) {
    if (event && event.preventDefault) event.preventDefault();

    const modal = document.getElementById("publish-modal-container");
    const metadataEditor = document.querySelector(
      '[data-controller~="metadata-editor"]',
    );
    if (!metadataEditor) {
      console.error("metadata-editor element not found");
      return;
    }

    // Collect field values from the modal.
    const values = {};
    if (modal) {
      modal.querySelectorAll('input[type="radio"]:checked').forEach((input) => {
        const name = this._extractMetadataFieldName(input.name);
        if (name) values[name] = input.value;
      });
      modal
        .querySelectorAll(
          'input[name^="metadata_fields"]:not([type="radio"]):not([type="checkbox"]), select[name^="metadata_fields"]',
        )
        .forEach((input) => {
          const name = this._extractMetadataFieldName(input.name);
          const trimmed = input.value.trim();
          if (name && trimmed) values[name] = trimmed;
        });
    }

    // Apply each value to the main metadata editor (source of truth).
    Object.entries(values).forEach(([fieldName, value]) => {
      this.applyMetadataField(fieldName, value);
    });

    // Force status to 'published' (matters when the trigger was the
    // Publish button rather than a status-select change).
    const statusField = metadataEditor.querySelector(
      '[data-metadata-field="status"]',
    );
    if (statusField) statusField.value = "published";

    // Notify metadata-editor that the publish was confirmed (so it
    // doesn't try to revert the status select on cancel cleanup).
    document.dispatchEvent(
      new CustomEvent("publish-modal:confirmed", { bubbles: true }),
    );

    // Close modal and submit the main Save form.
    if (modal) modal.innerHTML = "";
    this.setScrollLock(false);

    const form = document.getElementById(`${this.resourceTypeValue}-form`);
    if (form) {
      form.requestSubmit();
    } else {
      console.error("Main editor form not found");
    }
  }

  cancelPublish(event) {
    // Note: deliberately NOT calling preventDefault here. The Cancel
    // button is type="button" so it has no default action to suppress,
    // and the "Generate SKU" link inside the modal also fires this so
    // the publish modal closes — but we want Turbo to follow that link
    // and load the SKU generator into its own frame.

    // Tell metadata-editor so it can revert the status select if this
    // was triggered by a status-change.
    document.dispatchEvent(
      new CustomEvent("publish-modal:cancelled", { bubbles: true }),
    );

    const modal = document.getElementById("publish-modal-container");
    if (modal) modal.innerHTML = "";
    this.setScrollLock(false);

    // Restore the unsaved-changes warning since we're not actually saving.
    this.isSaving = false;
    window.addEventListener("beforeunload", this.beforeUnloadHandler);
  }

  _extractMetadataFieldName(rawName) {
    const match = (rawName || "").match(/^metadata_fields\[(.+)\]$/);
    return match ? match[1] : null;
  }

  // The Unpublish button is a form submit. Intercept it, confirm via the styled
  // modal, and submit the stashed form on "Unpublish". confirmedUnpublish lets
  // the re-issued submit through.
  confirmUnpublish(event) {
    if (this.confirmedUnpublish) return; // already confirmed via the modal
    event.preventDefault();
    this.pendingUnpublishForm = event.currentTarget;

    if (this.hasUnpublishModalTarget) {
      this.unpublishModalTarget.classList.remove("hidden");
    } else {
      // Fallback for any page without the modal.
      if (
        window.confirm(
          "Unpublish this item? Your changes will be saved and it will be removed from your site.",
        )
      ) {
        this.submitUnpublish();
      }
    }
  }

  submitUnpublish() {
    this.confirmedUnpublish = true;
    this.isSaving = true; // save + navigate; don't trip the dirty guard
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    if (this.hasUnpublishModalTarget) {
      this.unpublishModalTarget.classList.add("hidden");
    }
    if (this.pendingUnpublishForm) this.pendingUnpublishForm.requestSubmit();
  }

  cancelUnpublish() {
    if (this.hasUnpublishModalTarget) {
      this.unpublishModalTarget.classList.add("hidden");
    }
    this.pendingUnpublishForm = null;
  }

  unpublishModalBackdrop(event) {
    if (event.target === this.unpublishModalTarget) this.cancelUnpublish();
  }

  // ========== HELPER METHODS ==========

  autoExpandTextarea() {
    this.textareaTarget.style.height = "auto";
    this.textareaTarget.style.height = this.textareaTarget.scrollHeight + "px";
  }

  wrapSelectionWithSavedPosition(prefix, suffix, placeholder = "") {

    // Check if textarea currently has focus and a selection
    const hasFocus = document.activeElement === this.textareaTarget;
    const hasSelection =
      this.textareaTarget.selectionStart !== this.textareaTarget.selectionEnd;

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
    }

    const start = this.textareaTarget.selectionStart;
    const end = this.textareaTarget.selectionEnd;

    const selectedText = this.textareaTarget.value.substring(start, end);
    const content = selectedText || placeholder;
    const insertion = prefix + content + suffix;

    document.execCommand("insertText", false, insertion);

    if (!selectedText && placeholder) {
      const selectStart = start + prefix.length;
      const selectEnd = selectStart + placeholder.length;
      this.textareaTarget.setSelectionRange(selectStart, selectEnd);
    }

    // Clear saved position
    this.lastCursorPosition = null;
  }

  // Keep the old method for backwards compatibility if needed elsewhere
  wrapSelection(prefix, suffix, placeholder = "") {
    this.wrapSelectionWithSavedPosition(prefix, suffix, placeholder);
  }

  handleBeforeUnload(event) {
    if (this.isDirty()) {
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

        return;
      }
    }

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

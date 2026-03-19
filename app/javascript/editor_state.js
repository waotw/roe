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

    if (!savedState) return;

    const state = JSON.parse(savedState);

    // Use the saved elementId if available, otherwise fall back to textareaId
    const elementToRestore = state.elementId
      ? document.getElementById(state.elementId)
      : document.getElementById(textareaId);

    if (!elementToRestore) return;

    // Restore on next tick to ensure DOM is ready
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

      // Clear after restoring
      sessionStorage.removeItem(stateKey);
    }, 0);
  },

  init(textareaId) {
    const textarea = document.getElementById(textareaId);
    if (!textarea) return;

    // Restore state on page load
    this.restore(textareaId);

    // Save state before navigating away
    window.addEventListener("beforeunload", () => {
      this.save(textareaId);
    });
  },
};

// Make EditorState globally available
window.EditorState = EditorState;

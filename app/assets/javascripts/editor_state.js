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

  restore(textareaId) {
    const stateKey = `editorState:${window.location.pathname}`;
    const savedState = sessionStorage.getItem(stateKey);

    if (!savedState) return;

    const state = JSON.parse(savedState);
    const textarea = document.getElementById(textareaId);

    if (!textarea) return;

    // Restore on next tick to ensure DOM is ready
    setTimeout(() => {
      textarea.scrollTop = state.scrollPosition;
      textarea.focus();
      textarea.setSelectionRange(state.cursorPosition, state.cursorPosition);

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

    // Also save when form submits (for same-page updates)
    const form = textarea.closest("form");
    if (form) {
      form.addEventListener("submit", () => {
        this.save(textareaId);
      });
    }
  },
};

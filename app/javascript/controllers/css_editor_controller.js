import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["textarea", "unsavedIndicator"];
  static values = {
    themeName: String,
    previewId: String,
  };

  connect() {
    console.log("CSS Editor connected");
    this.hasUnsavedChanges = false;
    this.originalContent = this.textareaTarget.value;

    // Scroll lock variables
    this.lastScrollTop = window.scrollY;

    // Set up keyboard shortcuts
    document.addEventListener("keydown", this.handleKeyboard.bind(this));

    // Set up beforeunload warning
    window.addEventListener("beforeunload", this.handleBeforeUnload.bind(this));

    // Track scroll position
    window.addEventListener("scroll", this.updateScrollPosition.bind(this));

    // Listen for save trigger to refresh preview
    this.checkForSaveTrigger();

    // Auto-expand textarea
    this.autoExpand();
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeyboard.bind(this));
    window.removeEventListener(
      "beforeunload",
      this.handleBeforeUnload.bind(this),
    );
    window.removeEventListener("scroll", this.updateScrollPosition.bind(this));
  }

  updateScrollPosition() {
    this.lastScrollTop = window.scrollY;
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

  trackChanges(e) {
    const currentContent = this.textareaTarget.value;
    this.hasUnsavedChanges = currentContent !== this.originalContent;

    if (this.hasUnsavedChanges) {
      this.unsavedIndicatorTarget.classList.remove("hidden");
    } else {
      this.unsavedIndicatorTarget.classList.add("hidden");
    }

    // Capture scroll immediately before any changes
    const scrollBeforeInput = window.scrollY;

    // Expand textarea
    this.autoExpand();

    // Check scroll after changes
    requestAnimationFrame(() => {
      const scrollAfterInput = window.scrollY;
      const scrollDelta = scrollAfterInput - scrollBeforeInput;

      this.debugBottomDetection(scrollBeforeInput);

      // If browser auto-scrolled down (caret near bottom)
      if (scrollDelta > 0) {
        console.log("✅ Near bottom - browser scrolled", scrollDelta, "px");

        // Cap the scroll to a reasonable amount (e.g., max 40px at a time)
        const maxScrollAmount = 40;

        if (scrollDelta > maxScrollAmount) {
          // Browser scrolled too much, reduce it
          const cappedScroll = scrollBeforeInput + maxScrollAmount;
          console.log(
            "   Capping scroll from",
            scrollDelta,
            "px to",
            maxScrollAmount,
            "px",
          );
          window.scrollTo(0, cappedScroll);
        }
        // Otherwise, let the natural scroll stand
      } else if (scrollDelta < 0) {
        // Scrolled up - restore position
        console.log("🔒 Locking - scrolled up");
        window.scrollTo(0, scrollBeforeInput);
      }
    });
  }

  lockScrollDuringInput(scrollBeforeInput) {
    // This method is no longer needed - remove it
  }

  lockScrollDuringInput(scrollBeforeInput) {
    const scrollAfterInput = window.scrollY;
    const scrollDelta = scrollAfterInput - scrollBeforeInput;

    // If browser auto-scrolled down, caret is near bottom of viewport
    if (scrollDelta > 0) {
      // Allow the scroll and add breathing room
      console.log("✅ Allowing auto-scroll + adding 30px margin");
      window.scrollTo(0, scrollAfterInput + 0);
    } else if (scrollDelta !== 0) {
      // Lock any other scroll changes
      console.log("🔒 Locking scroll position");
      window.scrollTo(0, scrollBeforeInput);
    }
  }

  debugBottomDetection(scrollBeforeInput) {
    const scrollAfterInput = window.scrollY;
    const scrollDelta = scrollAfterInput - scrollBeforeInput;

    console.log("=== Bottom Detection Debug ===");
    console.log("Scroll before:", scrollBeforeInput);
    console.log("Scroll after:", scrollAfterInput);
    console.log("Scroll delta:", scrollDelta);

    // If browser scrolled down, the caret was near bottom of viewport
    if (scrollDelta > 0) {
      console.log(
        "🔵 NEAR BOTTOM - browser auto-scrolled down by",
        scrollDelta,
        "px",
      );
      console.log("   (caret was near bottom of visible area)");
    } else if (scrollDelta < 0) {
      console.log("⬆️  Scrolled up - unexpected");
    } else {
      console.log("⚪ Not near bottom - no auto-scroll occurred");
    }
  }

  autoExpand() {
    const textarea = this.textareaTarget;

    // Reset height to get accurate scrollHeight
    textarea.style.height = "auto";

    // Set to scrollHeight + small buffer for borders/padding
    textarea.style.height = textarea.scrollHeight + 4 + "px";

    // Don't restore scroll - let lockScrollDuringInput handle it
  }

  save(e) {
    if (e) e.preventDefault();

    const form = document.getElementById("theme-form");
    this.hasUnsavedChanges = false;
    this.unsavedIndicatorTarget.classList.add("hidden");

    // Save scroll position
    sessionStorage.setItem("cssEditorScrollPosition", window.scrollY);

    form.requestSubmit();
  }

  preview() {
    // Open site with theme preview parameter
    // Use previewId as window name so broadcasts reach it
    const previewUrl = `/?preview_theme=${this.themeNameValue}`;
    window.open(previewUrl, this.previewIdValue);
  }

  confirmCancel(e) {
    if (this.hasUnsavedChanges) {
      if (
        !confirm("You have unsaved changes. Are you sure you want to leave?")
      ) {
        e.preventDefault();
      }
    }
  }

  checkForSaveTrigger() {
    const trigger = document.getElementById("theme-saved-trigger");
    console.log("Checking for save trigger:", trigger ? "FOUND" : "NOT FOUND");

    if (trigger) {
      console.log(
        "Theme saved, broadcasting refresh to channel:",
        `preview-${this.previewIdValue}`,
      );
      this.broadcastRefresh();

      // Restore scroll position
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
    // Use same BroadcastChannel pattern as post editor
    if (typeof BroadcastChannel !== "undefined") {
      const channel = new BroadcastChannel(`preview-${this.previewIdValue}`);
      channel.postMessage({ action: "refresh" });
      channel.close();
    }
  }
}

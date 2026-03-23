// this is an old file, if I see this or share it, please remind me that this file is no longer in use.
document.addEventListener("turbo:load", function () {
  // Prevent multiple setups
  if (window.editorSetupComplete) {
    console.log("[Editor] Already set up, skipping...");
    return;
  }

  // Prevent scroll restoration
  if ("scrollRestoration" in history) {
    history.scrollRestoration = "manual";
  }

  const form = document.querySelector('[id$="-form"]');
  if (!form) return;

  // Read data attributes
  const resourceType = form.dataset.resourceType;
  const resourceId = form.dataset.resourceId;
  const previewId = `${resourceType}-${resourceId}`;
  const previewPath = form.dataset.previewPath;

  const collectionButtonTemplate = form.dataset.collectionTemplate;
  const asideButtonTemplate = form.dataset.asideTemplate;
  const postLinkButtonTemplate = form.dataset.postLinkTemplate;
  const pullquoteButtonTemplate = form.dataset.pullquoteTemplate;

  const contentTextarea = document.getElementById("content-textarea");

  // Track last cursor position
  let lastCursorPosition = null;

  if (contentTextarea) {
    contentTextarea.addEventListener("blur", (e) => {
      lastCursorPosition = contentTextarea.selectionStart;
      console.log("[BLUR] Saved cursor position:", lastCursorPosition);
    });

    contentTextarea.addEventListener("focus", (e) => {
      console.log(
        "[FOCUS] Textarea focused, current position:",
        contentTextarea.selectionStart,
      );
    });

    contentTextarea.addEventListener("input", () => {
      console.log("[INPUT] Clearing saved position");
      lastCursorPosition = null;
    });
  }

  EditorState.init("content-textarea");

  // Restore scroll positions
  const savedTextareaScroll = sessionStorage.getItem("editorScrollPosition");
  const savedWindowScroll = sessionStorage.getItem("windowScrollPosition");

  if (savedWindowScroll !== null) {
    setTimeout(() => {
      window.scrollTo(0, parseInt(savedWindowScroll));
      sessionStorage.removeItem("windowScrollPosition");
    }, 0);
  }

  if (savedTextareaScroll !== null && contentTextarea) {
    setTimeout(() => {
      contentTextarea.scrollTop = parseInt(savedTextareaScroll);
      sessionStorage.removeItem("editorScrollPosition");
    }, 0);
  }

  // Helper functions
  function wrapOrInsert(prefix, suffix, placeholder = "") {
    const textarea = document.getElementById("content-textarea");

    console.log(
      "[wrapOrInsert] START - savedPos:",
      lastCursorPosition,
      "current selection:",
      textarea.selectionStart,
    );

    // Get position BEFORE focusing
    const savedPos = lastCursorPosition;

    // Focus first
    textarea.focus();
    console.log(
      "[wrapOrInsert] After focus, selection:",
      textarea.selectionStart,
    );

    // Now restore the saved position if we have one
    if (savedPos !== null) {
      textarea.setSelectionRange(savedPos, savedPos);
      console.log("[wrapOrInsert] Restored position to:", savedPos);
    }

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    console.log("[wrapOrInsert] About to insert at:", start, "-", end);

    const selectedText = textarea.value.substring(start, end);
    const content = selectedText || placeholder;
    const insertion = prefix + content + suffix;

    document.execCommand("insertText", false, insertion);
    console.log("[wrapOrInsert] Inserted:", insertion);

    if (!selectedText && placeholder) {
      const selectStart = start + prefix.length;
      const selectEnd = selectStart + placeholder.length;
      textarea.setSelectionRange(selectStart, selectEnd);
    }

    lastCursorPosition = null;
    console.log("[wrapOrInsert] END - cleared saved position");
  }

  function insertCardTemplate(template) {
    const textarea = document.getElementById("content-textarea");
    const savedPos = lastCursorPosition;

    textarea.focus();

    if (savedPos !== null) {
      textarea.setSelectionRange(savedPos, savedPos);
    }

    const start = textarea.selectionStart;
    const fullText = "```card\n" + template + "\n```";
    document.execCommand("insertText", false, fullText);

    const placeholderIndex = template.indexOf("__PLACEHOLDER__");
    if (placeholderIndex !== -1) {
      const placeholderStart = start + "```card\n".length + placeholderIndex;
      const placeholderEnd = placeholderStart + "__PLACEHOLDER__".length;
      textarea.setSelectionRange(placeholderStart, placeholderEnd);
    } else {
      const cursorPos = start + fullText.length;
      textarea.setSelectionRange(cursorPos, cursorPos);
    }

    lastCursorPosition = null;
  }

  function previewPost() {
    if (!previewPath) {
      console.error("Preview path not defined");
      return;
    }

    const url = new URL(previewPath, window.location.origin);
    window.open(url.toString(), previewId);
  }

  function insertMedia(path, filename, position) {
    const textarea = document.getElementById("content-textarea");
    const markdown = `![${filename}](${path})`;

    textarea.focus({ preventScroll: true });
    textarea.setSelectionRange(position, position);

    document.execCommand("insertText", false, markdown);

    const lineHeight = parseInt(window.getComputedStyle(textarea).lineHeight);
    const lines = textarea.value
      .substring(0, textarea.selectionStart)
      .split("\n").length;
    textarea.scrollTop = (lines - 5) * lineHeight;
  }

  function searchPosts(query) {
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
              data-action="select-post"
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

  function selectPost(postData) {
    const slug = postData.url.replace(/^\/posts\//, "");

    let cardTemplate = "```card\ntype: post-link\nstyle: small\n";
    cardTemplate += `post: ${slug}\n`;
    cardTemplate += "```";

    const textarea = document.getElementById("content-textarea");
    textarea.focus({ preventScroll: true });
    document.execCommand("insertText", false, cardTemplate);

    closePostLinkModal();
  }

  function closePostLinkModal() {
    const modal = document.getElementById("post-link-modal");
    if (modal) {
      modal.remove();
    }
  }

  function showPostLinkPrompt() {
    document.getElementById("card-menu")?.classList.add("hidden");

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
          <button type="button" data-action="close-post-link-modal" class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">Cancel</button>
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

      searchTimeout = setTimeout(() => searchPosts(query), 300);
    });
  }

  // Track original values for unsaved changes warning
  let originalMetadata =
    document.querySelector('[name="metadata"]')?.value || "";
  let originalContent = document.querySelector('[name="content"]').value;

  function handleBeforeUnload(e) {
    let currentMetadata =
      document.querySelector('[name="metadata"]')?.value || "";
    let currentContent = document.querySelector('[name="content"]').value;

    if (
      currentMetadata !== originalMetadata ||
      currentContent !== originalContent
    ) {
      e.preventDefault();
      e.returnValue = "";
    }
  }

  window.addEventListener("beforeunload", handleBeforeUnload);

  // Event delegation for all button clicks
  document.addEventListener("click", (e) => {
    const target = e.target.closest("[data-action]");
    if (!target) return;

    const action = target.dataset.action;

    console.log(
      "[CLICK] Button action:",
      action,
      "savedPos:",
      lastCursorPosition,
    );

    switch (action) {
      case "insert-collection":
        e.preventDefault();
        console.log("[COLLECTION] START");
        const textarea = document.getElementById("content-textarea");
        const savedPos = lastCursorPosition;
        console.log("[COLLECTION] Saved position:", savedPos);

        textarea.focus();
        console.log(
          "[COLLECTION] After focus, selection:",
          textarea.selectionStart,
        );

        if (savedPos !== null) {
          textarea.setSelectionRange(savedPos, savedPos);
          console.log("[COLLECTION] Restored position to:", savedPos);
        }

        const start = textarea.selectionStart;
        console.log("[COLLECTION] About to insert at:", start);

        const collectionTemplate =
          "```collection\n" + collectionButtonTemplate + "\n```";
        document.execCommand("insertText", false, collectionTemplate);
        console.log("[COLLECTION] Inserted template");

        const cursorPos = start + "```collection\nheading: ".length;
        textarea.setSelectionRange(cursorPos, cursorPos);

        lastCursorPosition = null;
        console.log("[COLLECTION] END");
        break;

      case "trigger-media-upload":
        e.preventDefault();
        document.getElementById("media-upload")?.click();
        break;

      case "select-post":
        e.preventDefault();
        const postData = JSON.parse(target.dataset.post);
        selectPost(postData);
        break;

      case "close-post-link-modal":
        e.preventDefault();
        closePostLinkModal();
        break;
    }

    // Close card menu when clicking outside
    if (!target.closest("#card-menu") && action !== "toggle-card-menu") {
      document.getElementById("card-menu")?.classList.add("hidden");
    }

    // Close modal when clicking overlay
    if (e.target.id === "post-link-modal") {
      closePostLinkModal();
    }
  });

  // Handle publish/unpublish confirmations
  document.addEventListener("submit", (e) => {
    const form = e.target;

    if (form.dataset.action === "publish-confirm") {
      if (
        !confirm(
          "Publishing this post will save your changes and make it live on your site. Continue?",
        )
      ) {
        e.preventDefault();
        return;
      }
      window.removeEventListener("beforeunload", handleBeforeUnload);
    }

    if (form.dataset.action === "unpublish-confirm") {
      if (
        !confirm(
          "Unpublishing this post will save your changes and remove it from your site. Continue?",
        )
      ) {
        e.preventDefault();
        return;
      }
      window.removeEventListener("beforeunload", handleBeforeUnload);
    }
  });

  // Media upload handler
  document
    .getElementById("media-upload")
    ?.addEventListener("change", (event) => {
      const file = event.target.files[0];
      if (!file) return;

      const textarea = document.getElementById("content-textarea");
      const savedPosition = textarea.selectionStart;

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
            insertMedia(data.path, file.name, savedPosition);
          } else {
            alert("Upload failed: " + data.error);
          }
        })
        .catch((error) => {
          alert("Upload error: " + error);
        });

      event.target.value = "";
    });

  // Keyboard shortcuts
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "s") {
      e.preventDefault();

      window.removeEventListener("beforeunload", handleBeforeUnload);

      if (contentTextarea) {
        sessionStorage.setItem(
          "editorScrollPosition",
          contentTextarea.scrollTop,
        );
        sessionStorage.setItem("windowScrollPosition", window.scrollY);
      }

      document.getElementById(`${resourceType}-form`).requestSubmit();
    }

    if ((e.metaKey || e.ctrlKey) && e.key === "p") {
      e.preventDefault();
      previewPost();
    }
  });

  // Save editor state when browsing media
  document
    .getElementById("browse-media-link")
    ?.addEventListener("click", () => {
      EditorState.save("content-textarea");
    });

  // Handle visibility changes
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      EditorState.save("content-textarea");
    } else {
      EditorState.restore("content-textarea");
    }
  });

  // Create broadcast channel for preview refresh
  window.previewChannel = new BroadcastChannel(`preview-${previewId}`);

  // Form submission handler
  const formElement = document.getElementById(`${resourceType}-form`);
  formElement.addEventListener("submit", (e) => {
    window.removeEventListener("beforeunload", handleBeforeUnload);

    if (contentTextarea) {
      sessionStorage.setItem("editorScrollPosition", contentTextarea.scrollTop);
      sessionStorage.setItem("windowScrollPosition", window.scrollY);
    }

    window.previewChannel.postMessage({ action: "refresh" });
  });

  // Hide flash notice on input
  const flashNotice = document.querySelector(".flash-notice");
  if (flashNotice) {
    document.querySelectorAll("textarea").forEach((textarea) => {
      textarea.addEventListener("input", () => {
        flashNotice.style.display = "none";
      });
    });
  }

  // Check for post-saved trigger and broadcast refresh
  const savedTrigger = document.getElementById("post-saved-trigger");
  if (savedTrigger && savedTrigger.dataset.trigger === "refresh") {
    window.previewChannel?.postMessage({ action: "refresh" });
  }

  // At the very end, mark setup as complete
  window.editorSetupComplete = true;
});

// Clear the flag when navigating away
document.addEventListener("turbo:before-render", function () {
  window.editorSetupComplete = false;
});

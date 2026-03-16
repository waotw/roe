document.addEventListener("turbo:load", function () {
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

  EditorState.init("content-textarea");

  // Restore scroll positions FIRST
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

  function wrapOrInsert(prefix, suffix, placeholder = "") {
    const textarea = document.getElementById("content-textarea");
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selectedText = textarea.value.substring(start, end);

    const content = selectedText || placeholder;
    const insertion = prefix + content + suffix;

    textarea.focus({ preventScroll: true });
    document.execCommand("insertText", false, insertion);

    if (!selectedText && placeholder) {
      const selectStart = start + prefix.length;
      const selectEnd = selectStart + placeholder.length;
      textarea.setSelectionRange(selectStart, selectEnd);
    }
  }

  function insertCardTemplate(template) {
    const textarea = document.getElementById("content-textarea");
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
  }

  function previewPost() {
    if (!previewPath) {
      console.error("Preview path not defined");
      return;
    }

    const url = new URL(previewPath, window.location.origin);
    window.open(url.toString(), previewId);
  }

  let originalMetadata =
    document.querySelector('[name="metadata"]')?.value || "";
  let originalContent = document.querySelector('[name="content"]').value;

  window.handleBeforeUnload = function (e) {
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
  };

  function insertFootnote() {
    wrapOrInsert("(*", "*)", "footnote text here");
  }

  function insertItalic() {
    wrapOrInsert("_", "_", "italic text");
  }

  function insertStrike() {
    wrapOrInsert("~~", "~~", "struck text");
  }

  function insertBold() {
    wrapOrInsert("**", "**", "bold text");
  }

  function insertCollection() {
    const textarea = document.getElementById("content-textarea");
    const start = textarea.selectionStart;

    const collectionTemplate =
      "```collection\n" + collectionButtonTemplate + "\n```";

    document.execCommand("insertText", false, collectionTemplate);

    const cursorPos = start + "```collection\nheading: ".length;
    textarea.setSelectionRange(cursorPos, cursorPos);
  }

  function triggerMediaUpload() {
    document.getElementById("media-upload").click();
  }

  function toggleCardMenu(event) {
    event.stopPropagation();
    const menu = document.getElementById("card-menu");
    menu.classList.toggle("hidden");
  }

  document.addEventListener("click", (e) => {
    const menu = document.getElementById("card-menu");
    if (menu && !menu.classList.contains("hidden")) {
      menu.classList.add("hidden");
    }
  });

  function insertCard(type) {
    if (type === "pullquote") {
      insertCardTemplate(pullquoteButtonTemplate);
    } else if (type === "aside") {
      insertCardTemplate(asideButtonTemplate);
    } else if (type === "post-link") {
      insertCardTemplate(postLinkButtonTemplate);
    }

    document.getElementById("card-menu").classList.add("hidden");
  }

  function showPostLinkPrompt() {
    document.getElementById("card-menu").classList.add("hidden");

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
            <button onclick="closePostLinkModal()" class="uppercase text-xs px-1.5 py-0 border border-gray-800 bg-gray-200 hover:bg-gray-300 font-mono rounded-xs h-4.5 leading-none pt-[0.1rem]">Cancel</button>
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
              onclick='selectPost(${JSON.stringify(post)})'
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

  function selectPost(post) {
    const slug = post.url.replace(/^\/posts\//, "");

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

  document.addEventListener("click", (e) => {
    if (e.target.id === "post-link-modal") {
      closePostLinkModal();
    }
  });

  function handleMediaUpload(event) {
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

  window.addEventListener("beforeunload", handleBeforeUnload);

  // Keyboard shortcuts
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "s") {
      e.preventDefault();

      // Remove the listener
      window.removeEventListener("beforeunload", handleBeforeUnload);
      window.handleBeforeUnload = null;

      // Save scroll position before submit
      if (contentTextarea) {
        sessionStorage.setItem(
          "editorScrollPosition",
          contentTextarea.scrollTop,
        );
        sessionStorage.setItem("windowScrollPosition", window.scrollY);
      }

      // Use requestSubmit() instead of submit() to trigger event listeners
      document.getElementById(`${resourceType}-form`).requestSubmit();
    }

    if ((e.metaKey || e.ctrlKey) && e.key === "p") {
      e.preventDefault();
      previewPost();
    }
  });

  document
    .getElementById("browse-media-link")
    ?.addEventListener("click", () => {
      EditorState.save("content-textarea");
    });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      EditorState.save("content-textarea");
    } else {
      EditorState.restore("content-textarea");
    }
  });

  // Create a broadcast channel for this preview
  window.previewChannel = new BroadcastChannel(`preview-${previewId}`);

  const formElement = document.getElementById(`${resourceType}-form`);
  formElement.addEventListener("submit", (e) => {
    // Remove FIRST, synchronously
    window.removeEventListener("beforeunload", handleBeforeUnload);
    window.handleBeforeUnload = null; // Clear the reference too

    // Save scroll position
    if (contentTextarea) {
      sessionStorage.setItem("editorScrollPosition", contentTextarea.scrollTop);
      sessionStorage.setItem("windowScrollPosition", window.scrollY);
    }

    // Broadcast that content was saved
    previewChannel.postMessage({ action: "refresh" });
  });

  // Hide flash notice on any input
  const flashNotice = document.querySelector(".flash-notice");
  if (flashNotice) {
    document.querySelectorAll("textarea").forEach((textarea) => {
      textarea.addEventListener("input", () => {
        flashNotice.style.display = "none";
      });
    });
  }

  // Make functions globally available for onclick handlers
  window.wrapOrInsert = wrapOrInsert;
  window.insertCardTemplate = insertCardTemplate;
  window.previewPost = previewPost;
  window.insertFootnote = insertFootnote;
  window.insertItalic = insertItalic;
  window.insertStrike = insertStrike;
  window.insertBold = insertBold;
  window.insertCollection = insertCollection;
  window.triggerMediaUpload = triggerMediaUpload;
  window.toggleCardMenu = toggleCardMenu;
  window.insertCard = insertCard;
  window.showPostLinkPrompt = showPostLinkPrompt;
  window.selectPost = selectPost;
  window.closePostLinkModal = closePostLinkModal;
  window.handleMediaUpload = handleMediaUpload;
  window.insertMedia = insertMedia;

  // Check for post-saved trigger and broadcast refresh
  const savedTrigger = document.getElementById("post-saved-trigger");
  if (savedTrigger && savedTrigger.dataset.trigger === "refresh") {
    console.log("Flash notice detected, attempting broadcast...");
    if (window.previewChannel) {
      console.log("Sending refresh message via previewChannel");
      window.previewChannel.postMessage({ action: "refresh" });
    } else {
      console.log("ERROR: previewChannel is undefined!");
    }
  }
});

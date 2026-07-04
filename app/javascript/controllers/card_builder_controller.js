import { Controller } from "@hotwired/stimulus";

// Card builder. Mounted on the editor root alongside the `editor` controller,
// so the Card dropdown, this modal, and the textarea are all in scope. Opens
// pre-set to the type chosen in the dropdown; the type selector swaps which
// field group is shown. On insert, validates the active type's requirements,
// then serialises its non-empty fields into a ```card block (type first) and
// drops it at the cursor.
//
// The post-link `post` field is a typeahead over /admin/posts/search — the
// same endpoint the editor's old post-link prompt used.
//
// Deliberately isolated from editor_controller: it reads/writes the shared
// textarea directly rather than reaching into that controller's state.
export default class extends Controller {
  static targets = [
    "modal",
    "typeSelect",
    "group",
    "error",
    "postSearch",
    "postResults",
  ];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedPos = null;
    this.activeResult = -1;
  }

  // Opened from a Card dropdown item carrying data-card-type.
  open(event) {
    event?.preventDefault();
    const type = event?.currentTarget?.dataset?.cardType || "pullquote";
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;

    this.typeSelectTarget.value = type;
    this.showActiveGroup();
    this.clearError();
    this.hidePostResults();

    // Restore live placeholders if reopening with a post already chosen.
    if (
      type === "post-link" &&
      this.hasPostSearchTarget &&
      this.postSearchTarget.value.trim()
    ) {
      this.applyPostPlaceholders(this.postSearchTarget.value.trim());
    }

    const menu = this.element.querySelector('[data-editor-target="cardMenu"]');
    if (menu) menu.classList.add("hidden");

    this.modalTarget.style.display = "flex";
  }

  close(event) {
    event?.preventDefault();
    this.modalTarget.style.display = "none";
  }

  typeChanged() {
    this.showActiveGroup();
    this.clearError();
    this.hidePostResults();
  }

  fieldChanged(event) {
    const el = event.target;
    el.classList.toggle("cb-empty", !el.value);
    this.clearError();
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    } else if (event.key === "Enter" && event.target.tagName === "INPUT") {
      // Fields live inside the post <form>; don't let Enter submit it.
      event.preventDefault();
    }
  }

  insert(event) {
    event?.preventDefault();
    const group = this.activeGroup();
    if (!group) return;

    const error = this.validate(group);
    if (error) {
      this.showError(error);
      return;
    }

    const type = this.typeSelectTarget.value;
    const lines = [`type: ${type}`];
    group.querySelectorAll("[data-cb-field]").forEach((el) => {
      const value = el.value.trim();
      if (value === "") return; // only fields with a value get written
      lines.push(`${el.dataset.cbField}: ${value}`);
    });

    const block = "```card\n" + lines.join("\n") + "\n```";
    this.close();

    if (this.textarea) {
      this.textarea.focus({ preventScroll: true });
      const pos = this.savedPos ?? this.textarea.selectionStart;
      this.textarea.setSelectionRange(pos, pos);
      document.execCommand("insertText", false, block);
    }
  }

  // --- validation ----------------------------------------------------------

  // Returns an error string when the active group's requirements aren't met,
  // otherwise null. Requirements come from the group's data attributes, which
  // are rendered from CardBuilderSchema (the single source of truth).
  validate(group) {
    const val = (key) => {
      const el = group.querySelector(`[data-cb-field="${key}"]`);
      return el ? el.value.trim() : "";
    };
    const list = (attr) =>
      (group.dataset[attr] || "").split(",").filter(Boolean);

    const missing = list("cbRequiredAll").filter((k) => !val(k));
    if (missing.length) return `Please fill in: ${missing.join(", ")}.`;

    const any = list("cbRequiredAny");
    if (any.length && !any.some((k) => val(k))) {
      return `Please provide at least one of: ${any.join(" or ")}.`;
    }
    return null;
  }

  showError(message) {
    this.errorTarget.textContent = message;
    this.errorTarget.hidden = false;
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true;
  }

  // --- post-link typeahead -------------------------------------------------

  postSearchInput(event) {
    const input = event.target;
    input.classList.toggle("cb-empty", !input.value);
    this.clearError();

    const q = input.value.trim();
    clearTimeout(this.searchTimer);
    if (q.length < 1) {
      this.hidePostResults();
      this.clearPostPlaceholders(); // no post → no inherited values to show
      return;
    }
    this.searchTimer = setTimeout(() => this.fetchPosts(q), 250);
  }

  fetchPosts(q) {
    fetch(`/admin/posts/search?q=${encodeURIComponent(q)}`)
      .then((r) => (r.ok ? r.json() : []))
      .then((items) =>
        this.renderPostResults(Array.isArray(items) ? items : []),
      )
      .catch(() => this.hidePostResults());
  }

  renderPostResults(items) {
    const ul = this.postResultsTarget;
    ul.innerHTML = "";
    if (!items.length) {
      this.hidePostResults();
      return;
    }
    this.activeResult = -1;
    items.slice(0, 20).forEach((item) => {
      const li = document.createElement("li");
      li.className =
        "px-2 py-1 cursor-pointer hover:bg-gray-100 flex justify-between gap-2";
      li.dataset.urlName = item.url_name;

      const title = document.createElement("span");
      title.textContent = item.title;
      const type = document.createElement("span");
      type.className = "text-gray-400";
      type.textContent = item.type;

      li.append(title, type);
      // mousedown (not click) so selection fires before the input blurs.
      li.addEventListener("mousedown", (e) => {
        e.preventDefault();
        this.selectPost(item.url_name);
      });
      ul.append(li);
    });
    ul.classList.remove("hidden");
  }

  selectPost(urlName) {
    const input = this.postSearchTarget;
    input.value = urlName;
    input.classList.toggle("cb-empty", !urlName);
    this.hidePostResults();
    input.focus();
    // Show the chosen post's values as live placeholders on the override
    // fields (empty → still inherited/live; typed → an explicit override).
    this.applyPostPlaceholders(urlName);
  }

  // The override fields whose placeholders mirror the linked post's values.
  static PLACEHOLDER_KEYS = [
    "title",
    "subtitle",
    "excerpt",
    "url",
    "author",
    "date",
    "image",
  ];

  applyPostPlaceholders(slug) {
    if (!slug) {
      this.clearPostPlaceholders();
      return;
    }
    fetch(`/admin/posts/card_fields?post=${encodeURIComponent(slug)}`)
      .then((r) => (r.ok ? r.json() : {}))
      .then((data) => this.setPlaceholders(data || {}))
      .catch(() => {});
  }

  placeholderFields() {
    const group = this.groupTargets.find(
      (g) => g.dataset.cbType === "post-link",
    );
    if (!group) return [];
    return this.constructor.PLACEHOLDER_KEYS.map((k) =>
      group.querySelector(`[data-cb-field="${k}"]`),
    ).filter(Boolean);
  }

  setPlaceholders(data) {
    this.placeholderFields().forEach((el) => {
      el.placeholder = (data[el.dataset.cbField] ?? "").toString();
    });
  }

  clearPostPlaceholders() {
    this.placeholderFields().forEach((el) => {
      el.placeholder = "";
    });
  }

  postSearchKeydown(event) {
    const ul = this.postResultsTarget;
    const open = !ul.classList.contains("hidden");
    const items = Array.from(ul.children);

    if (event.key === "ArrowDown" && open && items.length) {
      event.preventDefault();
      this.activeResult = Math.min(this.activeResult + 1, items.length - 1);
      this.highlightResult(items);
    } else if (event.key === "ArrowUp" && open && items.length) {
      event.preventDefault();
      this.activeResult = Math.max(this.activeResult - 1, 0);
      this.highlightResult(items);
    } else if (event.key === "Enter" && open && items.length) {
      // Choose the highlighted (or first) result; keep it from bubbling to the
      // modal's Enter guard / the form.
      event.preventDefault();
      event.stopPropagation();
      const idx = this.activeResult >= 0 ? this.activeResult : 0;
      this.selectPost(items[idx].dataset.urlName);
    } else if (event.key === "Escape" && open) {
      // Close the results list first, not the whole modal.
      event.preventDefault();
      event.stopPropagation();
      this.hidePostResults();
    }
  }

  highlightResult(items) {
    items.forEach((li, i) =>
      li.classList.toggle("bg-gray-100", i === this.activeResult),
    );
  }

  hidePostResults() {
    if (this.hasPostResultsTarget)
      this.postResultsTarget.classList.add("hidden");
  }

  // --- helpers -------------------------------------------------------------

  showActiveGroup() {
    const type = this.typeSelectTarget.value;
    this.groupTargets.forEach((g) => {
      g.hidden = g.dataset.cbType !== type;
    });
  }

  activeGroup() {
    const type = this.typeSelectTarget.value;
    return this.groupTargets.find((g) => g.dataset.cbType === type);
  }
}

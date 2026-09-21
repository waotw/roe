import { Controller } from "@hotwired/stimulus";

// Card builder. Mounted on the editor root alongside the `editor` controller,
// so the Card dropdown, this modal, and the textarea are all in scope. Opens
// pre-set to the type chosen in the dropdown; the type selector swaps which
// field group is shown. On insert, validates the active type's requirements,
// then serialises its non-empty fields into a ```card block (type first) and
// drops it at the cursor.
//
// Reference fields (post-link's `post`, product-link's `product`) are
// typeaheads; each field carries its own search endpoint via data attributes,
// so one generic handler serves both. Choosing a reference shows the linked
// item's live values as placeholders on the override fields.
//
// Deliberately isolated from editor_controller: it reads/writes the shared
// textarea directly rather than reaching into that controller's state.
//
// The Card ▼ toolbar button reads the caret (like the nav / collection / gallery
// builders): when the caret is on a ```card block it turns amber, reads "Edit
// Card", and a click opens that card directly (skipping the dropdown, since the
// type is known from the block); the insert button reads "Update" and rewrites
// the block in place. Caret elsewhere is the old dropdown-and-insert behaviour.
export default class extends Controller {
  static targets = ["modal", "typeSelect", "group", "error", "toggleButton", "insertButton"];

  // Override fields whose placeholders mirror the referenced item's values.
  static PLACEHOLDER_KEYS = [
    "title",
    "subtitle",
    "excerpt",
    "description",
    "url",
    "author",
    "date",
    "image",
  ];

  connect() {
    this.textarea = this.element.querySelector(
      '[data-editor-target="textarea"]',
    );
    this.savedPos = null;
    // { start, finish, indent } line range while editing an existing block.
    this.editing = null;
    this.snapshotDefaults();

    if (this.textarea) {
      this._refresh = () => this.updateToggleButton();
      ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
        this.textarea.addEventListener(ev, this._refresh));
      document.addEventListener("selectionchange", this._refresh);
    }
    this.updateToggleButton();
  }

  disconnect() {
    if (!this._refresh) return;
    ["keyup", "click", "select", "input", "focus"].forEach((ev) =>
      this.textarea?.removeEventListener(ev, this._refresh));
    document.removeEventListener("selectionchange", this._refresh);
  }

  // First handler on the Card button, ahead of editor#toggleCardMenu. On a
  // ```card block it opens that card for editing and stops the dropdown from
  // also opening; anywhere else it does nothing and the dropdown opens as usual.
  caretClick(event) {
    const block = this.blockAtCursor();
    if (!block) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    this.openForEdit(block);
  }

  openForEdit(block) {
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;
    this.editing = { start: block.start, finish: block.finish, indent: block.indent };
    this.clearError();
    this.hideAllResults();
    this.loadBlock(block.body);
    this.updateInsertLabel();
    const menu = this.element.querySelector('[data-editor-target="cardMenu"]');
    if (menu) menu.classList.add("hidden");
    this.modalTarget.style.display = "flex";
  }

  // Opened from a Card dropdown item (or the Product button) carrying
  // data-card-type. Always a fresh insert.
  open(event) {
    event?.preventDefault();
    const type = event?.currentTarget?.dataset?.cardType || "pullquote";
    this.savedPos = this.textarea ? this.textarea.selectionStart : null;
    this.editing = null;

    this.typeSelectTarget.value = type;
    this.showActiveGroup();
    this.clearError();
    this.hideAllResults();
    this.updateInsertLabel();

    // Restore live placeholders if reopening with a reference already chosen.
    const group = this.activeGroup();
    const ref = group?.querySelector("[data-cb-search-url]");
    if (ref && ref.value.trim()) this.applyPlaceholders(group, ref.value.trim());

    const menu = this.element.querySelector('[data-editor-target="cardMenu"]');
    if (menu) menu.classList.add("hidden");

    this.modalTarget.style.display = "flex";
  }

  // --- caret detection ------------------------------------------------------

  // The ```card block enclosing the caret, or null. Returns the inclusive line
  // range (both fences), the opening fence's indent, and the body lines. A
  // leading indent is allowed (a card nested in a footnote); any other fence
  // between the caret and an opener means the caret isn't in a card block.
  blockAtCursor() {
    const ta = this.textarea;
    if (!ta) return null;
    const lines = ta.value.split("\n");
    const caretLine = ta.value.slice(0, ta.selectionStart).split("\n").length - 1;

    let open = -1, indent = "";
    for (let i = caretLine; i >= 0; i--) {
      const m = lines[i].match(/^(\s*)```card\s*$/);
      if (m) { open = i; indent = m[1]; break; }
      if (/^\s*```/.test(lines[i])) return null;
    }
    if (open < 0) return null;

    let close = open + 1;
    while (close < lines.length && !/^\s*```\s*$/.test(lines[close])) close++;
    if (close >= lines.length || caretLine > close) return null;

    return { start: open, finish: close, indent, body: lines.slice(open + 1, close) };
  }

  // Parse a ```card body into a { key: value } map, matching parse_card_config:
  // a line `key: value` (lowercase key) starts a field; a following line with
  // no `key:` continues the previous value only when that key is a prose key
  // (`text`), which is what lets a pull quote hold several paragraphs. Values
  // are trimmed, like the renderer's transform_values(&:strip).
  static PROSE_KEYS = ["text"];
  static OPTION_RE = /^[ \t]*([a-z_][a-z0-9_]*)[ \t]*:[ \t]?(.*)$/;

  parseBlock(body) {
    const cfg = {};
    let current = null;
    body.forEach((line) => {
      const m = line.match(this.constructor.OPTION_RE);
      if (m) {
        current = m[1];
        cfg[current] = m[2];
      } else if (current && this.constructor.PROSE_KEYS.includes(current)) {
        cfg[current] = `${cfg[current]}\n${line}`;
      }
    });
    Object.keys(cfg).forEach((k) => { cfg[k] = cfg[k].trim(); });
    return cfg;
  }

  // Fill the form from a card block: switch to its type, show that group, then
  // set each field within it. A reference card (post-link/product-link) also
  // re-fetches the linked item's live placeholders for the override fields.
  loadBlock(body) {
    const cfg = this.parseBlock(body);
    const type = cfg.type || "pullquote";
    this.typeSelectTarget.value = type;
    this.showActiveGroup();

    const group = this.activeGroup();
    if (!group) return;
    Object.entries(cfg).forEach(([k, v]) => {
      if (k === "type") return;
      const el = group.querySelector(`[data-cb-field="${k}"]`);
      if (!el) return;
      el.value = v;
      el.classList.toggle("cb-empty", !el.value);
    });

    const ref = group.querySelector("[data-cb-search-url]");
    if (ref && ref.value.trim()) this.applyPlaceholders(group, ref.value.trim());
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget || !this.textarea) return;
    const editing = !!this.blockAtCursor();
    const b = this.toggleButtonTarget;
    if (this._defaultLabel === undefined) this._defaultLabel = b.innerHTML;
    if (editing) b.textContent = "Edit Card";
    else b.innerHTML = this._defaultLabel;
    b.classList.toggle("bg-amber-100", editing);
    b.classList.toggle("hover:bg-amber-200", editing);
    b.classList.toggle("border-amber-700", editing);
    b.classList.toggle("text-amber-900", editing);
    b.classList.toggle("bg-gray-200", !editing);
    b.classList.toggle("hover:bg-gray-300", !editing);
    b.classList.toggle("border-gray-800", !editing);
  }

  // "Update" when editing an existing block, "Insert" for a fresh one.
  updateInsertLabel() {
    if (this.hasInsertButtonTarget) {
      this.insertButtonTarget.textContent = this.editing ? "Update" : "Insert";
    }
  }

  close(event) {
    event?.preventDefault();
    this.modalTarget.style.display = "none";
  }

  // Cancel discards the current entries and closes. A plain close (X, backdrop,
  // Escape) leaves them as-is so reopening resumes where you left off; a
  // successful insert also resets, so the next card starts fresh.
  cancel(event) {
    event?.preventDefault();
    this.editing = null;
    this.resetFields();
    this.close();
  }

  // Snapshot the modal's pristine field state once, so insert/cancel restore it.
  snapshotDefaults() {
    this.defaults = Array.from(
      this.modalTarget.querySelectorAll("input, select, textarea"),
    ).map((el) => ({
      el,
      value: el.value,
      checked: el.checked,
      placeholder: el.getAttribute("placeholder"),
    }));
  }

  resetFields() {
    (this.defaults || []).forEach(({ el, value, checked, placeholder }) => {
      el.value = value;
      el.checked = checked;
      if (placeholder === null) el.removeAttribute("placeholder");
      else el.setAttribute("placeholder", placeholder);
      el.classList.toggle("cb-empty", !el.value);
    });
    this.clearError();
    this.hideAllResults();
  }

  typeChanged() {
    this.showActiveGroup();
    this.clearError();
    this.hideAllResults();
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
      // A field still showing the site default is left out, so the block keeps
      // following that setting if it changes later. Changing it back to the
      // default counts as unchanged — the setting already says that.
      if (value === (el.dataset.cbDefault ?? "")) return;
      lines.push(`${el.dataset.cbField}: ${value}`);
    });

    // Editing indents the block to match the fence it replaces (a card nested
    // in a footnote keeps its indent); a fresh insert isn't indented. A prose
    // `text:` value can hold newlines, so indent each of its lines too.
    const indent = this.editing ? this.editing.indent : "";
    const bodyLines = lines
      .join("\n")
      .split("\n")
      .map((l) => indent + l);
    const block = indent + "```card\n" + bodyLines.join("\n") + "\n" + indent + "```";
    const editing = this.editing;
    this.editing = null;
    this.close();

    if (this.textarea) {
      this.textarea.focus({ preventScroll: true });
      const ta = this.textarea;
      let from, to;
      if (editing) {
        const all = ta.value.split("\n");
        from = all.slice(0, editing.start).join("\n").length + (editing.start > 0 ? 1 : 0);
        to = all.slice(0, editing.finish + 1).join("\n").length;
      } else {
        const pos = this.savedPos ?? ta.selectionStart;
        from = pos;
        to = pos;
      }
      ta.setSelectionRange(from, to);
      document.execCommand("insertText", false, block);
      const end = from + block.length;
      ta.setSelectionRange(end, end);
    }

    this.resetFields();
    this.updateToggleButton();
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

  // --- reference typeahead (post-link / product-link) ----------------------

  refSearchInput(event) {
    const input = event.target;
    input.classList.toggle("cb-empty", !input.value);
    this.clearError();

    const group = input.closest("[data-cb-type]");
    const ul = input.parentElement.querySelector("[data-cb-results]");
    const q = input.value.trim();
    clearTimeout(this.searchTimer);
    if (q.length < 1) {
      this.hideResults(ul);
      this.clearPlaceholders(group); // no reference → no inherited values
      return;
    }
    this.searchTimer = setTimeout(
      () => this.fetchRefs(input, ul, group, q),
      250,
    );
  }

  fetchRefs(input, ul, group, q) {
    const url = input.dataset.cbSearchUrl;
    const param = input.dataset.cbSearchParam || "q";
    fetch(`${url}?${param}=${encodeURIComponent(q)}`)
      .then((r) => (r.ok ? r.json() : []))
      .then((items) =>
        this.renderRefs(input, ul, group, Array.isArray(items) ? items : []),
      )
      .catch(() => this.hideResults(ul));
  }

  renderRefs(input, ul, group, items) {
    ul.innerHTML = "";
    if (!items.length) {
      this.hideResults(ul);
      return;
    }
    ul.dataset.active = "-1";
    items.slice(0, 20).forEach((item) => {
      const li = document.createElement("li");
      li.className =
        "px-2 py-1 cursor-pointer hover:bg-gray-100 flex justify-between gap-2 items-center";
      // Products come grouped: variants are indented under their primary.
      if (item.indent) li.classList.add("pl-6");
      li.dataset.urlName = item.url_name;

      const title = document.createElement("span");
      title.textContent = item.title;

      // Badge: post/page/doc type, or for products the primary/variant marker.
      const badge = document.createElement("span");
      badge.className = "text-gray-400 text-xs whitespace-nowrap";
      if (item.primary) badge.textContent = "primary";
      else if (item.variant) badge.textContent = item.variant;
      else badge.textContent = item.type || "";

      li.append(title, badge);
      // mousedown (not click) so selection fires before the input blurs.
      li.addEventListener("mousedown", (e) => {
        e.preventDefault();
        this.selectRef(input, ul, group, item.url_name);
      });
      ul.append(li);
    });
    ul.classList.remove("hidden");
  }

  selectRef(input, ul, group, urlName) {
    input.value = urlName;
    input.classList.toggle("cb-empty", !urlName);
    this.hideResults(ul);
    input.focus();
    // Show the chosen item's values as live placeholders on the override
    // fields (empty → still inherited/live; typed → an explicit override).
    this.applyPlaceholders(group, urlName);
  }

  refSearchKeydown(event) {
    const input = event.target;
    const ul = input.parentElement.querySelector("[data-cb-results]");
    const open = ul && !ul.classList.contains("hidden");
    const items = ul ? Array.from(ul.children) : [];
    if (!open || !items.length) return; // let the modal handler take Enter/Esc

    let active = parseInt(ul.dataset.active ?? "-1", 10);
    if (event.key === "ArrowDown") {
      event.preventDefault();
      active = Math.min(active + 1, items.length - 1);
      ul.dataset.active = active;
      this.highlight(items, active);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      active = Math.max(active - 1, 0);
      ul.dataset.active = active;
      this.highlight(items, active);
    } else if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      const idx = active >= 0 ? active : 0;
      this.selectRef(
        input,
        ul,
        input.closest("[data-cb-type]"),
        items[idx].dataset.urlName,
      );
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation(); // close the list, not the whole modal
      this.hideResults(ul);
    }
  }

  highlight(items, active) {
    items.forEach((li, i) => li.classList.toggle("bg-gray-100", i === active));
  }

  hideResults(ul) {
    if (ul) ul.classList.add("hidden");
  }

  hideAllResults() {
    this.element
      .querySelectorAll("[data-cb-results]")
      .forEach((ul) => ul.classList.add("hidden"));
  }

  // --- live placeholders ---------------------------------------------------

  applyPlaceholders(group, slug) {
    if (!group) return;
    if (!slug) {
      this.clearPlaceholders(group);
      return;
    }
    // card_fields resolves posts, pages, products, and docs by slug.
    fetch(`/admin/posts/card_fields?post=${encodeURIComponent(slug)}`)
      .then((r) => (r.ok ? r.json() : {}))
      .then((data) => this.setPlaceholders(group, data || {}))
      .catch(() => {});
  }

  placeholderFields(group) {
    if (!group) return [];
    return this.constructor.PLACEHOLDER_KEYS.map((k) =>
      group.querySelector(`[data-cb-field="${k}"]`),
    ).filter(Boolean);
  }

  setPlaceholders(group, data) {
    this.placeholderFields(group).forEach((el) => {
      el.placeholder = (data[el.dataset.cbField] ?? "").toString();
    });
  }

  clearPlaceholders(group) {
    this.placeholderFields(group).forEach((el) => {
      el.placeholder = "";
    });
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

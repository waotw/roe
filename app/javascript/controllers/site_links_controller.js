import { Controller } from "@hotwired/stimulus";

// Navigation builder for the layout editor (header / footer / sidebar).
//
// One picker over everything a layout can link to — pages, feeds, member
// pages, custom URLs — ordered by hand, then written into the textarea as a
// `menu` collection block or as plain markdown links.
//
// The toolbar button reads the caret:
//   ADD NAVIGATION   — nothing under the caret; the picker starts empty and
//                      inserts at the caret.
//   EDIT NAVIGATION  — the caret is on a run of `- [text](url)` lines, or
//                      inside a ```collection block with template: menu.
//                      The picker opens pre-filled from it and the insert
//                      buttons replace it. Editing works both ways: links
//                      can become a menu, a menu can become links, or
//                      either can just be updated in kind.
//
// Nothing is saved here; the layout is saved as usual. Its own controller,
// so the editor's inline script (save, preview, cursor restore) is untouched.
export default class extends Controller {
  static targets = [
    "modal", "available", "chosen", "name", "style", "error",
    "toggleButton", "customText", "customUrl", "modeLabel",
    "insertMenu", "insertMarkdown", "copy", "collectionHint"
  ];
  static values = {
    convertUrl: String,
    textarea: String,
    links: Object, // { pages: [[label, url_name, path]] }
  };

  LINK_LINE = /^\s*[-*+]\s+\[([^\]]*)\]\(([^)\s]+)\)\s*$/;
  MENU_LINK = /^\[([^\]]*)\]\(([^)\s]+)\)$/;

  connect() {
    this.chosen = [];   // [{ text, target, url_name, confidence }]
    this.editing = null; // { kind: "links"|"menu", start, finish } while editing
    const refresh = () => this.updateToggleButton();
    ["keyup", "click", "select", "input", "focus"].forEach((ev) => this.textarea.addEventListener(ev, refresh));
    document.addEventListener("selectionchange", refresh);
    this.updateToggleButton();
  }

  get textarea() {
    return document.querySelector(this.textareaValue || '[name="content"]');
  }

  get pages() {
    return this.linksValue.pages || [];
  }

  // ── What's under the caret ───────────────────────────────────────────

  selectedLineRange() {
    const ta = this.textarea;
    const lineAt = (pos) => ta.value.slice(0, pos).split("\n").length - 1;
    const endPos = ta.selectionEnd > ta.selectionStart && ta.value[ta.selectionEnd - 1] === "\n"
      ? ta.selectionEnd - 1 : ta.selectionEnd;
    return { start: lineAt(ta.selectionStart), finish: lineAt(Math.max(ta.selectionStart, endPos)) };
  }

  // The navigation the caret is in: a run of link lines, or a menu block.
  navAtCursor() {
    const lines = this.textarea.value.split("\n");
    const { start, finish } = this.selectedLineRange();

    // A menu block enclosing the caret?
    let open = -1;
    for (let i = start; i >= 0; i--) {
      if (/^```\s*$/.test(lines[i])) break;
      if (/^```collection\s*$/.test(lines[i])) { open = i; break; }
    }
    if (open >= 0) {
      let close = open + 1;
      while (close < lines.length && !/^```\s*$/.test(lines[close])) close++;
      if (close < lines.length && close >= finish) {
        const body = lines.slice(open + 1, close);
        if (body.some((l) => /^template:\s*menu\s*$/.test(l))) {
          return { kind: "menu", start: open, finish: close, body };
        }
      }
    }

    const isLink = (i) => i >= 0 && i < lines.length && this.LINK_LINE.test(lines[i]);
    if (finish > start) {
      let s = start, f = finish;
      while (s <= f && !isLink(s)) s++;
      while (f >= s && !isLink(f)) f--;
      return s <= f ? { kind: "links", start: s, finish: f, lines: lines.slice(s, f + 1) } : null;
    }
    if (!isLink(start)) return null;
    let s = start, f = start;
    while (isLink(s - 1)) s--;
    while (isLink(f + 1)) f++;
    return { kind: "links", start: s, finish: f, lines: lines.slice(s, f + 1) };
  }

  updateToggleButton() {
    if (!this.hasToggleButtonTarget) return;
    const nav = this.navAtCursor();
    const b = this.toggleButtonTarget;
    b.textContent = nav ? "Edit Navigation" : "Add Navigation";
    b.classList.toggle("bg-blue-100", !nav);
    b.classList.toggle("hover:bg-blue-200", !nav);
    b.classList.toggle("border-gray-800", !nav);
    b.classList.toggle("bg-amber-100", !!nav);
    b.classList.toggle("hover:bg-amber-200", !!nav);
    b.classList.toggle("border-amber-700", !!nav);
    b.classList.toggle("text-amber-900", !!nav);
  }

  // ── Opening ──────────────────────────────────────────────────────────

  async open(event) {
    event?.preventDefault();
    this.errorTarget.textContent = "";
    const nav = this.navAtCursor();

    if (!nav) {
      this.editing = null;
      this.chosen = [];
      this.nameTarget.value = "nav";
      if (this.hasStyleTarget) this.styleTarget.value = "vertical";
    } else if (nav.kind === "menu") {
      this.editing = { kind: "menu", start: nav.start, finish: nav.finish };
      this.loadMenu(nav.body);
    } else {
      this.editing = { kind: "links", start: nav.start, finish: nav.finish };
      const ok = await this.loadLinks(nav.lines);
      if (!ok) return;
    }

    this.render();
    this.show();
  }

  // Parse a menu block's body back into rows. A url_name resolves to its
  // page (by the pages list); an inline link stays a link.
  loadMenu(body) {
    const get = (key) => (body.find((l) => l.startsWith(`${key}:`)) || "").slice(key.length + 1).trim();
    this.nameTarget.value = get("collection") || "nav";
    if (this.hasStyleTarget) this.styleTarget.value = get("style") || "vertical";

    const byUrl = new Map(this.pages.map(([label, url, path]) => [url.toLowerCase(), { label, url, path }]));
    this.chosen = this.splitOrder(get("order")).map((entry) => {
      const m = entry.match(this.MENU_LINK);
      if (m) return { text: m[1].trim(), target: m[2], url_name: null };
      const p = byUrl.get(entry.toLowerCase());
      return p ? { text: p.label, target: p.path, url_name: p.url }
               : { text: entry, target: `/${entry}`, url_name: entry, missing: true };
    });
  }

  // Comma split that respects a markdown link's brackets/parens.
  splitOrder(s) {
    const out = []; let buf = "", depth = 0;
    for (const ch of s) {
      if (ch === "[" || ch === "(") depth++;
      else if ((ch === "]" || ch === ")") && depth > 0) depth--;
      if (ch === "," && depth === 0) { out.push(buf.trim()); buf = ""; }
      else buf += ch;
    }
    out.push(buf.trim());
    return out.filter(Boolean);
  }

  // Ask the server to guess a page for each markdown link.
  async loadLinks(lines) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    const res = await fetch(this.convertUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ content: lines.join("\n") }),
    });
    const data = await res.json();
    if (!res.ok) {
      this.errorTarget.textContent = data.error || "Couldn't read the links.";
      this.show();
      return false;
    }
    this.chosen = data.rows.map((r) => ({ text: r.text, target: r.target, url_name: r.url_name, confidence: r.confidence }));
    this.nameTarget.value = "nav";
    return true;
  }

  // ── Picking ──────────────────────────────────────────────────────────

  toggle(event) {
    const el = event.currentTarget;
    const item = { text: el.dataset.text, target: el.dataset.target, url_name: el.dataset.urlName || null };
    const i = this.chosen.findIndex((c) => c.target === item.target);
    if (i >= 0) this.chosen.splice(i, 1); else this.chosen.push(item);
    this.render();
  }

  addCustom(event) {
    event?.preventDefault();
    const text = this.customTextTarget.value.trim();
    const target = this.customUrlTarget.value.trim();
    if (!text || !target) return;
    this.chosen.push({ text, target, url_name: null });
    this.customTextTarget.value = "";
    this.customUrlTarget.value = "";
    this.render();
  }

  move(event) {
    const i = Number(event.currentTarget.dataset.index), j = i + Number(event.currentTarget.dataset.dir);
    if (j < 0 || j >= this.chosen.length) return;
    [this.chosen[i], this.chosen[j]] = [this.chosen[j], this.chosen[i]];
    this.render();
  }

  remove(event) {
    this.chosen.splice(Number(event.currentTarget.dataset.index), 1);
    this.render();
  }

  repoint(event) {
    const i = Number(event.currentTarget.dataset.index);
    const url = event.currentTarget.value || null;
    const p = url ? this.pages.find(([, u]) => u === url) : null;
    this.chosen[i].url_name = url;
    if (p) { this.chosen[i].text = p[0]; this.chosen[i].target = p[2]; }
    this.chosen[i].confidence = null;
    this.chosen[i].missing = false;
    this.render();
  }

  nameChanged() {
    this.updateHint();
  }

  // ── Rendering ────────────────────────────────────────────────────────

  render() {
    const picked = new Set(this.chosen.map((c) => c.target));
    this.availableTarget.querySelectorAll("[data-target]").forEach((el) =>
      el.classList.toggle("bg-amber-100", picked.has(el.dataset.target)));

    this.chosenTarget.innerHTML = "";
    if (!this.chosen.length) this.chosenTarget.innerHTML = '<li class="text-xs text-gray-400 py-2">Nothing picked yet.</li>';
    this.chosen.forEach((c, i) => this.chosenTarget.appendChild(this.chosenRow(c, i)));

    const any = this.chosen.length > 0;
    [this.insertMenuTarget, this.insertMarkdownTarget, this.copyTarget].forEach((b) => (b.disabled = !any));

    // Button labels say what will happen to what's under the caret.
    const kind = this.editing?.kind;
    this.insertMenuTarget.textContent = kind === "menu" ? "Update menu" : kind === "links" ? "Convert to menu" : "Insert as menu";
    this.insertMarkdownTarget.textContent = kind === "links" ? "Update markdown links" : kind === "menu" ? "Convert to markdown links" : "Insert as markdown links";
    this.modeLabelTarget.textContent = kind === "menu" ? "Editing the menu under the cursor" : kind === "links" ? "Editing the links under the cursor" : "";
    this.updateHint();
  }

  updateHint() {
    if (!this.hasCollectionHintTarget) return;
    this.collectionHintTarget.textContent = (this.nameTarget.value || "nav").trim();
  }

  chosenRow(c, i) {
    const li = document.createElement("li");
    li.className = "flex items-center gap-2 py-1 border-t border-gray-200 text-xs";

    const label = document.createElement("span");
    label.className = "flex-1 font-mono truncate" + (c.missing ? " text-red-700" : "");
    label.textContent = c.url_name ? `${c.text} → ${c.url_name}` : `[${c.text}](${c.target})`;
    label.title = c.missing ? "No page has this url_name" : "";
    li.appendChild(label);

    // While editing, any row's page can be corrected.
    if (this.editing) {
      const sel = document.createElement("select");
      sel.className = "font-mono text-xs px-1 py-0.5 border border-gray-300 max-w-[12rem]";
      sel.dataset.index = i;
      sel.dataset.action = "change->site-links#repoint";
      sel.appendChild(new Option("Keep as a link", "", !c.url_name, !c.url_name));
      this.pages.forEach(([pl, url]) => sel.appendChild(new Option(`${pl} (${url})`, url, c.url_name === url, c.url_name === url)));
      li.appendChild(sel);
      if (c.confidence === "text" || c.confidence === "title") {
        const warn = document.createElement("span");
        warn.className = "text-amber-700"; warn.title = "Guessed — check it"; warn.textContent = "?";
        li.appendChild(warn);
      }
    }

    const btn = (t, attrs) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "px-1.5 border border-gray-400 bg-white hover:bg-gray-100 font-mono rounded-xs";
      b.textContent = t;
      Object.assign(b.dataset, attrs, { index: i });
      return b;
    };
    li.append(btn("↑", { action: "site-links#move", dir: -1 }), btn("↓", { action: "site-links#move", dir: 1 }), btn("×", { action: "site-links#remove" }));
    return li;
  }

  // ── Output ───────────────────────────────────────────────────────────

  menuBlock() {
    const name = (this.nameTarget.value || "nav").trim();
    const style = this.hasStyleTarget ? this.styleTarget.value : "";
    const entries = this.chosen.map((c) => c.url_name || `[${c.text}](${c.target})`);
    const lines = ["```collection", `collection: ${name}`, "template: menu"];
    if (style && style !== "vertical") lines.push(`style: ${style}`);
    lines.push(`order: ${entries.join(", ")}`, "```");
    return lines;
  }

  markdownLines() {
    return this.chosen.map((c) => `- [${c.text}](${c.target})`);
  }

  insertMenu(event) { event?.preventDefault(); this.write(this.menuBlock()); }
  insertMarkdown(event) { event?.preventDefault(); this.write(this.markdownLines()); }

  async copy(event) {
    event?.preventDefault();
    try { await window.copyToClipboard(this.markdownLines().join("\n")); this.flash(event.currentTarget, "Copied"); }
    catch (_) { this.flash(event.currentTarget, "Press ⌘/Ctrl-C"); }
  }

  // Replace what's being edited, or insert at the caret on its own lines.
  //
  // Goes through execCommand("insertText") rather than setting .value, so
  // the change lands in the textarea's own undo history: ⌘Z / Ctrl-Z puts
  // the previous text back, ⌘⇧Z redoes, and it composes with whatever
  // was typed before and after. Setting .value directly would wipe that
  // history. execCommand is deprecated but every browser still honours it
  // for exactly this, and the .value path stays as the fallback.
  write(newLines) {
    const ta = this.textarea;
    let from, to, text;

    if (this.editing) {
      const lines = ta.value.split("\n");
      from = lines.slice(0, this.editing.start).join("\n").length + (this.editing.start > 0 ? 1 : 0);
      to = lines.slice(0, this.editing.finish + 1).join("\n").length;
      text = newLines.join("\n");
    } else {
      from = ta.selectionStart;
      to = ta.selectionEnd;
      const before = ta.value.slice(0, from), after = ta.value.slice(to);
      const lead = before.length && !before.endsWith("\n") ? "\n" : "";
      const tail = after.length && !after.startsWith("\n") ? "\n" : "";
      text = lead + newLines.join("\n") + tail;
    }

    ta.focus();
    ta.setSelectionRange(from, to);
    let done = false;
    try { done = document.execCommand("insertText", false, text); } catch (_) { done = false; }
    if (!done) {
      ta.setRangeText(text, from, to, "end");
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }

    // Leave the caret at the end of what was written.
    const pos = from + text.length;
    ta.setSelectionRange(pos, pos);
    this.close();
    ta.focus();
    this.updateToggleButton();
  }

  flash(button, text) {
    const original = button.textContent;
    button.textContent = text;
    setTimeout(() => (button.textContent = original), 1500);
  }

  show() { this.modalTarget.hidden = false; }
  close(event) { event?.preventDefault(); this.modalTarget.hidden = true; }
  backdrop(event) { if (event.target === this.modalTarget) this.close(); }
}

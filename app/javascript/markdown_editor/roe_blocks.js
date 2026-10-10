// Roe-anji blocks in the live editor.
//
// ```collection, ```card, ```gallery, ```form, ```button and ```search are
// fenced code to the markdown grammar. Here each one collapses to a labelled
// card while the caret is elsewhere, and opens back into its raw text the
// moment the caret moves in — by clicking the card, or by arrowing into it.
//
// A block that won't render shows the parser's own amber warning box instead
// of a card. Those come from the server (POST /admin/markdown/blocks), which
// runs each block through HasMarkdownExtensions in preview mode, so "broken"
// means exactly what it means on the page. Results are cached by block text;
// only blocks that changed are asked about again.
//
// Block replacement has to come from a StateField (CodeMirror won't let a view
// plugin hide line breaks), which is why this lives apart from live_preview.js.

import {
  StateField,
  StateEffect,
  RangeSetBuilder,
  Prec,
} from "@codemirror/state";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  WidgetType,
  keymap,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";

// The kinds HasMarkdownExtensions skips when it protects ordinary code fences.
// Keep in step with the list at the top of to_html.
export const ROE_BLOCK_KINDS = new Set([
  "collection",
  "card",
  "gallery",
  "form",
  "button",
  "search",
]);

// The word after the opening fence, lowercased. "" when there isn't one.
export function fenceKind(state, node) {
  const info = node.getChild("CodeInfo");
  if (!info) return "";
  return state.doc
    .sliceString(info.from, info.to)
    .trim()
    .split(/\s/)[0]
    .toLowerCase();
}

// ── Labels ─────────────────────────────────────────────────────────────────

// `key: value` lines, the way the server's block parsers read them.
function readConfig(body) {
  const config = {};
  for (const line of body.split("\n")) {
    const m = /^\s*([\w-]+)\s*:\s*(.*)$/.exec(line);
    if (m && !(m[1] in config))
      config[m[1]] = m[2].replace(/^["']|["']$/g, "").trim();
  }
  return config;
}

const KIND_NAMES = {
  collection: "Collection",
  card: "Card",
  gallery: "Gallery",
  form: "Form",
  button: "Button",
  search: "Search",
};

const titleCase = (s) =>
  s.replace(/[-_]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

// The card's header: the block's name, and the details worth seeing at a
// glance. "Collection" + "posts · 6 items".
export function describeBlock(kind, body) {
  const config = readConfig(body);
  const name = KIND_NAMES[kind] || titleCase(kind);
  const parts = [];

  switch (kind) {
    case "collection": {
      if (config.source) parts.push(config.source);
      if (config.layout) parts.push(config.layout);
      if (config.limit) parts.push(`${config.limit} items`);
      if (config.tags || config.tag)
        parts.push(`#${config.tags || config.tag}`);
      break;
    }
    case "card": {
      if (config.type) parts.push(titleCase(config.type));
      break;
    }
    case "gallery": {
      const images = (body.match(/!\[[^\]]*\]\([^)]+\)/g) || []).length;
      parts.push(`${images} image${images === 1 ? "" : "s"}`);
      if (
        /^\s*carousel\s*:\s*true/m.test(body) ||
        /^\s*carousel\s*$/m.test(body)
      ) {
        parts.push("carousel");
      }
      break;
    }
    case "form":
    case "button": {
      const forWhat = config.for || config.type;
      parts.push(
        forWhat ? titleCase(forWhat) : kind === "button" ? "Product" : "",
      );
      break;
    }
    case "search": {
      const scope = config.scope || config.source;
      if (scope) parts.push(scope);
      break;
    }
  }
  return { name, detail: parts.filter(Boolean).join(" · ") };
}

// ── Widgets ────────────────────────────────────────────────────────────────

// One faded row of a closed block. The source line, shortened where the full
// text only gets in the way:
//
//   ![su-san-lee-1](/media/images/su-san-lee-1.jpg)(*At dusk*)
//     → ![su-san-lee-1] At dusk         (the path is what makes these long)
//   caption: A long walk                 → **caption:** A long walk
//
// Display only — the document still holds the full line, and opening the block
// shows it.
const IMAGE_LINE =
  /^(\s*)!\[([^\]]*)\]\(([^)\s]*)[^)]*\)(?:\s*\(\*?(.*?)\*?\))?\s*$/;
const SETTING_LINE = /^(\s*)([\w-]+:)(.*)$/;

function fillRow(row, text) {
  if (!text.trim()) {
    row.textContent = "\u00a0"; // a blank line still takes up a line
    return;
  }

  const image = IMAGE_LINE.exec(text);
  if (image) {
    const [, indent, alt, src, caption] = image;
    const name = alt || src.split("/").pop() || "image";
    row.append(indent);
    const label = document.createElement("span");
    label.className = "roe-md-block-image";
    label.textContent = `![${name}]`;
    row.appendChild(label);
    if (caption) row.append(` ${caption}`);
    return;
  }

  const setting = SETTING_LINE.exec(text);
  if (setting) {
    const [, indent, key, rest] = setting;
    row.append(indent);
    const strong = document.createElement("span");
    strong.className = "roe-md-block-key";
    strong.textContent = key;
    row.appendChild(strong);
    row.append(rest);
    return;
  }

  row.textContent = text;
}

// The card takes the place of the block's text exactly: one row per line of
// source, each row one line tall, starting where the opening fence starts and
// no wider than the longest line. So opening a block (caret in) and closing it
// (caret out) changes how it looks but moves nothing — the text below stays
// put, and a click lands on the line it looks like it's on.
//
//   ```collection        →  Collection  posts · 6 items     (the header row)
//   source: posts        →  source: posts                   (faded)
//   limit: 6             →  limit: 6                        (faded)
//   ```                  →                                  (bottom edge)
//
// Nothing in here may add height: no vertical margin, padding or border —
// the edge is drawn with an inset box-shadow, which takes no room.
//
// An indented block — one inside a footnote — is drawn indented: the whole
// card, header included, starts where the fence's ``` starts. The rows show
// the lines with that shared indent taken off, so only indentation *within*
// the block shows.

// A line with the fence's indent removed, when it has it. A line indented
// less (a mistake the renderer would complain about) is left as it is.
function stripIndent(line, indent) {
  return indent && line.startsWith(indent) ? line.slice(indent.length) : line;
}

class BlockCardWidget extends WidgetType {
  // auto: a gallery Roe makes from images on consecutive lines, with no
  // fence. Every row is an image line, so there's no fence line to carry the
  // header — the name goes at the end of the first row instead.
  constructor(kind, label, lines, indent, from, warnings, auto = false) {
    super();
    this.kind = kind;
    this.label = label; // { name, detail }
    this.lines = lines; // the body: source lines between the fences
    this.indent = indent; // columns the fence is indented by
    this.from = from;
    this.warnings = warnings; // null = not checked yet, [] = fine
    this.auto = auto;
  }

  eq(other) {
    return (
      other.kind === this.kind &&
      other.auto === this.auto &&
      other.label.name === this.label.name &&
      other.label.detail === this.label.detail &&
      other.indent === this.indent &&
      other.from === this.from &&
      other.lines.join("\n") === this.lines.join("\n") &&
      JSON.stringify(other.warnings) === JSON.stringify(this.warnings)
    );
  }

  labelSpans() {
    const name = document.createElement("span");
    name.className = "roe-md-block-name";
    name.textContent = this.label.name;
    const spans = [name];
    if (this.label.detail) {
      const detail = document.createElement("span");
      detail.className = "roe-md-block-detail";
      detail.textContent = this.label.detail;
      spans.push(detail);
    }
    return spans;
  }

  toDOM(view) {
    const wrap = document.createElement("div");
    wrap.className = "roe-md-block";
    wrap.dataset.kind = this.kind;
    wrap.setAttribute("role", "button");
    wrap.title = this.auto
      ? "Images on lines next to each other show as a gallery. Click to edit."
      : "Click to edit this block";
    // In `ch`, the width of one character of the editor's monospace font, so
    // the card lines up with the ``` exactly. Spacing, not padding: the
    // indent area stays clickable as part of the block.
    if (this.indent) {
      wrap.classList.add("roe-md-block-indented");
      wrap.style.setProperty("--block-indent", `${this.indent}ch`);
    }

    if (this.warnings && this.warnings.length) {
      wrap.classList.add("roe-md-block-broken");
      // The parser's own box, as the preview would show it. It's HTML Roe
      // generated and escaped itself (dev_warning), not anything typed here.
      for (const w of this.warnings) {
        if (w.html) {
          const holder = document.createElement("div");
          holder.innerHTML = w.html;
          wrap.appendChild(holder.firstElementChild || holder);
        } else {
          const box = document.createElement("div");
          box.className = "roe-md-block-error";
          box.textContent = `⚠️ ${w.title} — ${w.message}`;
          wrap.appendChild(box);
        }
      }
    } else if (this.auto) {
      const card = document.createElement("div");
      card.className = "roe-md-block-card roe-md-block-auto";
      this.lines.forEach((text, i) => {
        const row = document.createElement("div");
        row.className = "roe-md-block-row roe-md-block-line";
        if (i === 0) {
          const body = document.createElement("span");
          body.className = "roe-md-block-text";
          fillRow(body, text);
          const tag = document.createElement("span");
          tag.className = "roe-md-block-tag";
          tag.append(...this.labelSpans());
          row.append(body, tag);
        } else {
          fillRow(row, text);
        }
        card.appendChild(row);
      });
      wrap.appendChild(card);
    } else {
      const card = document.createElement("div");
      card.className = "roe-md-block-card";

      const head = document.createElement("div");
      head.className = "roe-md-block-row roe-md-block-head";
      head.append(...this.labelSpans());
      card.appendChild(head);

      for (const text of this.lines) {
        const row = document.createElement("div");
        row.className = "roe-md-block-row roe-md-block-line";
        fillRow(row, text);
        card.appendChild(row);
      }

      // The closing fence's line: the card's bottom edge.
      const foot = document.createElement("div");
      foot.className = "roe-md-block-row roe-md-block-foot";
      foot.textContent = "\u00a0";
      card.appendChild(foot);

      wrap.appendChild(card);
    }

    // Open the block for editing with the caret on the line that was clicked.
    // Every row is a line of the source, so that's the line under the pointer
    // — except the header (the ``` line), which goes to the first setting:
    // a caret parked on the fence is rarely where anyone wants to type.
    wrap.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const rows = [...wrap.querySelectorAll(".roe-md-block-row")];
      const row = event.target.closest?.(".roe-md-block-row");
      const doc = view.state.doc;
      const first = doc.lineAt(this.from).number;
      // Auto galleries have no fence line, so every row is a line to edit.
      const index = Math.max(this.auto ? 0 : 1, rows.indexOf(row));
      const lineNo = Math.min(first + index, doc.lines);
      view.dispatch({ selection: { anchor: doc.line(lineNo).to } });
      view.focus();
    });
    return wrap;
  }

  ignoreEvent() {
    return false;
  }
}

// ── Server checks ──────────────────────────────────────────────────────────

const setWarnings = StateEffect.define(); // Map<source, warnings[]>

const warningsField = StateField.define({
  create: () => new Map(),
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setWarnings)) {
        const next = new Map(value);
        for (const [source, warnings] of effect.value)
          next.set(source, warnings);
        return next;
      }
    }
    return value;
  },
});

// Every Roe-anji block in the document: { from, to, kind, source }.
function findBlocks(state) {
  const blocks = [];
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name !== "FencedCode") return;
      const kind = fenceKind(state, node.node);
      if (ROE_BLOCK_KINDS.has(kind)) {
        blocks.push({
          from: node.from,
          to: node.to,
          kind,
          source: state.doc.sliceString(node.from, node.to),
        });
      }
      return false;
    },
  });
  return blocks;
}

function selectionTouches(state, from, to) {
  return state.selection.ranges.some((r) => r.from <= to && r.to >= from);
}

// ── Automatic galleries ────────────────────────────────────────────────────
//
// Two or more images on consecutive lines, with no blank line between them,
// render as a gallery — HasMarkdownExtensions#process_auto_galleries wraps
// them in a ```gallery fence before anything else sees them. This finds the
// same runs, by the same rules, so the editor shows a gallery card exactly
// where the page will have a gallery:
//
//   - a line counts when, trimmed, it's only an image (with an optional
//     (*caption*) after it)
//   - nothing inside a ``` fence counts — every line starting with ``` flips
//     in or out, the way the server counts them
//   - nothing inside a footnote counts: the server leaves footnote images
//     alone, because a fence at column 0 would end the note
//
// Keep in step with process_auto_galleries.
const AUTO_IMAGE = /^!\[([^\]]*)\]\(([^)]+)\)\s*(?:\(\*([^*]+)\*\))?$/;
const FOOTNOTE_START = /^\[\^[^\]]+\]:/;

const runsCache = new WeakMap();

// [{ from, to, firstLine, lastLine }] — character and line ranges of each run.
export function autoGalleryRuns(state) {
  const doc = state.doc;
  if (runsCache.has(doc)) return runsCache.get(doc);

  const runs = [];
  let fenced = false;
  let inFootnote = false;
  let start = null;
  let count = 0;

  const flush = (lastLine) => {
    if (count >= 2) {
      runs.push({
        from: doc.line(start).from,
        to: doc.line(lastLine).to,
        firstLine: start,
        lastLine,
      });
    }
    start = null;
    count = 0;
  };

  for (let n = 1; n <= doc.lines; n++) {
    const text = doc.line(n).text;
    const trimmed = text.trim();

    if (trimmed.startsWith("```")) {
      fenced = !fenced;
      if (fenced) flush(n - 1);
      continue;
    }
    if (fenced) continue;

    if (FOOTNOTE_START.test(text)) {
      flush(n - 1);
      inFootnote = true;
      continue;
    }
    if (inFootnote) {
      if (trimmed === "" || /^\s{4,}/.test(text)) continue;
      inFootnote = false;
    }

    if (AUTO_IMAGE.test(trimmed)) {
      if (start === null) start = n;
      count++;
    } else {
      flush(n - 1);
    }
  }
  flush(doc.lines);

  runsCache.set(doc, runs);
  return runs;
}

// Line numbers inside a run, for live_preview.js: those lines show as text
// while the gallery is open, not as inline images.
export function autoGalleryLines(state) {
  const lines = new Set();
  for (const run of autoGalleryRuns(state)) {
    for (let n = run.firstLine; n <= run.lastLine; n++) lines.add(n);
  }
  return lines;
}

function buildBlockDecorations(state) {
  const warnings = state.field(warningsField);
  // Fenced blocks and automatic galleries are found separately and never
  // overlap (auto galleries skip anything fenced); the builder needs them in
  // document order.
  const cards = [];
  for (const block of findBlocks(state)) {
    // An unclosed fence runs to the end of the document. Collapsing that would
    // swallow everything after it, so leave it as text — the markdown check
    // already reports the missing fence.
    const closed = /\n\s*```+\s*$/.test(block.source);
    if (!closed) continue;

    const sourceLines = block.source.split("\n");
    const body = sourceLines.slice(1, -1).join("\n");
    // Inside a footnote the fence is indented ("    ```gallery"), and the
    // syntax tree's block starts after those spaces. Replacing from there
    // would leave the spaces behind as an empty line of their own above the
    // card, which the caret could land in. So the card takes the whole line,
    // from its first column, and draws the indent itself instead.
    const fenceLine = state.doc.lineAt(block.from);
    const indent = state.doc.sliceString(fenceLine.from, block.from);
    const from = /^[ \t]*$/.test(indent) ? fenceLine.from : block.from;
    if (selectionTouches(state, from, block.to)) continue;
    const widget = new BlockCardWidget(
      block.kind,
      describeBlock(block.kind, body),
      sourceLines.slice(1, -1).map((line) => stripIndent(line, indent)),
      indent.replace(/\t/g, "    ").length,
      from,
      warnings.has(block.source) ? warnings.get(block.source) : null,
    );
    cards.push({ from, to: block.to, widget });
  }

  for (const run of autoGalleryRuns(state)) {
    if (selectionTouches(state, run.from, run.to)) continue;
    const lines = state.doc.sliceString(run.from, run.to).split("\n");
    const widget = new BlockCardWidget(
      "gallery",
      { name: "Gallery", detail: `${lines.length} images · automatic` },
      lines.map((line) => line.trim()),
      0,
      run.from,
      [], // nothing to check: two images in a row can't be misconfigured
      true,
    );
    cards.push({ from: run.from, to: run.to, widget });
  }

  const builder = new RangeSetBuilder();
  cards
    .sort((a, b) => a.from - b.from)
    .forEach(({ from, to, widget }) =>
      builder.add(from, to, Decoration.replace({ widget, block: true })),
    );
  return builder.finish();
}

const blockField = StateField.define({
  create: (state) => buildBlockDecorations(state),
  update(value, tr) {
    if (
      tr.docChanged ||
      tr.selection ||
      tr.effects.some((e) => e.is(setWarnings)) ||
      syntaxTree(tr.startState) !== syntaxTree(tr.state)
    ) {
      return buildBlockDecorations(tr.state);
    }
    return value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

// Asks the server about blocks it hasn't seen: once on load, then a beat
// after typing stops. Blocks already answered are never sent again, so editing
// prose costs no requests at all.
function blockChecker(url) {
  if (!url) return [];

  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.view = view;
        this.timer = null;
        this.inFlight = false;
        this.destroyed = false;
        this.schedule(0);
      }

      update(update) {
        if (update.docChanged) this.schedule(800);
      }

      destroy() {
        clearTimeout(this.timer);
        this.destroyed = true;
      }

      schedule(delay) {
        clearTimeout(this.timer);
        this.timer = setTimeout(() => this.run(), delay);
      }

      run() {
        if (this.destroyed) return;
        if (this.inFlight) return this.schedule(400);

        const known = this.view.state.field(warningsField);
        const pending = [
          ...new Set(findBlocks(this.view.state).map((b) => b.source)),
        ].filter((source) => !known.has(source));
        if (!pending.length) return;

        this.inFlight = true;
        const body = new FormData();
        pending.forEach((source) => body.append("blocks[]", source));
        fetch(url, {
          method: "POST",
          headers: {
            "X-CSRF-Token":
              document.querySelector('meta[name="csrf-token"]')?.content || "",
            Accept: "application/json",
          },
          body,
          credentials: "same-origin",
        })
          .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
          .then((data) => {
            if (this.destroyed) return;
            const results = new Map();
            pending.forEach((source, i) =>
              results.set(source, data.blocks?.[i]?.warnings || []),
            );
            this.view.dispatch({ effects: setWarnings.of(results) });
          })
          .catch(() => {
            // Offline or signed out: the cards stay unchecked. Nothing here is
            // worth an error message — saving and the preview will say more.
          })
          .finally(() => {
            this.inFlight = false;
          });
      }
    },
  );
}

export function roeBlocks({ checkUrl } = {}) {
  return [warningsField, blockField, blockChecker(checkUrl), arrowIntoBlocks];
}

// CodeMirror steps over a collapsed block in one keypress, so from the keyboard
// a card could be passed but never opened. Arrowing onto one opens it instead:
// down lands on its first line of settings, up on its last.
function arrowInto(direction) {
  return (view) => {
    const { state } = view;
    const sel = state.selection.main;
    if (!sel.empty) return false;
    const line = state.doc.lineAt(sel.head);
    let target = null;
    state.field(blockField).between(0, state.doc.length, (from, to) => {
      if (direction > 0 && from === line.to + 1) {
        target = state.doc.lineAt(from).number + 1;
      } else if (direction < 0 && to === line.from - 1) {
        target = state.doc.lineAt(to).number - 1;
      }
      if (target) return false;
    });
    if (!target || target < 1 || target > state.doc.lines) return false;
    view.dispatch({
      selection: { anchor: state.doc.line(target).from },
      scrollIntoView: true,
      userEvent: "select",
    });
    return true;
  };
}

const arrowIntoBlocks = Prec.high(
  keymap.of([
    { key: "ArrowDown", run: arrowInto(1) },
    { key: "ArrowUp", run: arrowInto(-1) },
  ]),
);

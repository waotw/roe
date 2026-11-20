// Links to the site's own posts, pages, products and docs.
//
// A list of them opens:
//   - after `](/` in a Markdown link: picking one writes `/posts/x.md)`,
//     and fills in the link text with the title when the brackets are empty;
//   - after `[[`: picking one writes `posts/x]]`;
//   - on clicking an existing link to one of them, new style or old
//     (`[x](/posts/lab-full)`), so it can be pointed somewhere else.
//
// Links name files, not addresses (InternalLinks on the server): a file
// doesn't move when its title or url_name changes.
//
// Wikilinks are also drawn here: in SOURCE as written, coloured; in LIVE as
// the link alone (its text, or the item's title), with the brackets back
// when the caret is on it. One that names no file is red.

import { autocompletion, startCompletion } from "@codemirror/autocomplete";
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view";
import { StateEffect } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";

const LIST_URL = "/admin/internal_links";

// ── The list ──────────────────────────────────────────────────────────────

let items = null;
let loading = null;
const byRef = new Map();
const byName = new Map();
const byAddress = new Map();
const views = new Set();
const listLoaded = StateEffect.define();

function load() {
  loading ||= fetch(LIST_URL, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    .then((r) => (r.ok ? r.json() : { items: [] }))
    .catch(() => ({ items: [] }))
    .then((json) => {
      items = (json.items || []).map(prepare);
      for (const view of views) {
        if (view.dom.isConnected) view.dispatch({ effects: listLoaded.of(null) });
        else views.delete(view);
      }
      return items;
    });
  return loading;
}

function prepare(item) {
  const name = item.ref.split("/").pop();
  const prepared = {
    ...item,
    name,
    path: `/${item.ref}`,
    hay: [item.title, `/${item.ref}`, item.url_name, item.address].join(" ").toLowerCase(),
  };
  byRef.set(item.ref, prepared);
  byAddress.set(item.address, prepared);
  if (!byName.has(name)) byName.set(name, []);
  byName.get(name).push(prepared);
  return prepared;
}

// What a link target names, as the server reads it: `posts/x`, `/posts/x.md`,
// `x` when only one file is called that — or an old-style address.
function resolve(target) {
  if (!items) return undefined;
  const raw = (target || "").trim().split("#")[0];
  const ref = raw.replace(/^\//, "").replace(/\.md$/i, "");
  if (ref.includes("/")) return byRef.get(ref) || byAddress.get(raw) || null;
  const named = byName.get(ref) || [];
  if (named.length === 1) return named[0];
  return byAddress.get(raw) || null;
}

// An address on this site that a page lives at — not media or other files.
function internalUrl(url) {
  return (
    url.startsWith("/") &&
    !url.startsWith("//") &&
    !/^\/(media|system|theme|assets|rails)\//.test(url)
  );
}

// ── Where the caret is ────────────────────────────────────────────────────

const WIKI = /\[\[([^[\]|\n]*)(\|[^[\]\n]*)?\]\]/g;
const MD_LINK = /\[([^\]\n]*)\]\(([^()\s]*)\)/g;

// The link target the caret is in, as { kind, from, to, query, closed, ... }.
// While typing, only right after `[[` or `](/`; when opened on purpose
// (`explicit`: a click, or Ctrl-Space), anywhere on an internal link.
function spotAt(state, pos, explicit) {
  const line = state.doc.lineAt(pos);
  const col = pos - line.from;
  const before = line.text.slice(0, col);
  const after = line.text.slice(col);

  let m = before.match(/\[\[([^[\]|]*)$/);
  if (m) {
    const rest = after.match(/^[^[\]|]*/)[0];
    const tail = after.slice(rest.length);
    return {
      kind: "wiki",
      from: pos - m[1].length,
      to: pos + rest.length,
      query: m[1],
      closed: tail.startsWith("]]") || tail.startsWith("|"),
      current: m[1] + rest,
    };
  }

  // The address part, up to the caret. Spaces are allowed while the list is
  // open, so `/lab full` can narrow it by two words; picking replaces them.
  m = before.match(/\]\((\/[^()\n]*|[^()\s]*)$/);
  if (m) {
    const rest = after.match(/^[^()\s]*/)[0];
    const url = m[1] + rest;
    if (!explicit && !m[1].startsWith("/")) return null;
    if (url && !internalUrl(url)) return null;
    const openBracket = before.length - m[0].length;
    return {
      kind: "md",
      from: pos - m[1].length,
      to: pos + rest.length,
      query: m[1],
      closed: after.slice(rest.length).startsWith(")"),
      emptyText: before[openBracket - 1] === "[",
      current: url,
    };
  }

  if (!explicit) return null;

  // Anywhere else on a link: the click that opens it lands on the text.
  for (const w of line.text.matchAll(WIKI)) {
    if (col < w.index || col > w.index + w[0].length) continue;
    const from = line.from + w.index + 2;
    return { kind: "wiki", from, to: from + w[1].length, query: "", closed: true, current: w[1] };
  }
  for (const l of line.text.matchAll(MD_LINK)) {
    if (col < l.index || col > l.index + l[0].length || !internalUrl(l[2])) continue;
    const from = line.from + l.index + l[1].length + 3;
    return { kind: "md", from, to: from + l[2].length, query: "", closed: true, emptyText: false, current: l[2] };
  }
  return null;
}

// ── The completion source ─────────────────────────────────────────────────

function rank(query, current) {
  const q = query.toLowerCase().replace(/\.md$/, "").trim();
  const words = q.split(/\s+/).filter(Boolean);
  const bare = q.replace(/^\//, "");
  const score = (it) => {
    if (it === current) return -1;
    if (!q) return 2;
    if (it.ref === bare || it.name === bare || it.url_name === bare || it.address === q) return 0;
    if (it.title.toLowerCase().startsWith(q) || it.name.startsWith(bare)) return 1;
    return 2;
  };
  return items
    .filter((it) => it === current || words.every((w) => it.hay.includes(w)))
    .map((it) => ({ it, s: score(it) }))
    .sort((a, b) => a.s - b.s || b.it.updated - a.it.updated)
    .slice(0, 100)
    .map(({ it }) => it);
}

function option(item, spot) {
  const detail = item.url_name && item.url_name !== item.name ? `${item.path} • ${item.url_name}` : item.path;
  return {
    label: `${item.title} ${item.path}`,
    displayLabel: item.title,
    detail,
    draft: item.draft,
    apply: (view, _completion, from, to) => insert(view, item, spot, from, to),
  };
}

function insert(view, item, spot, from, to) {
  const changes = [];
  let text;
  let caretAfter;
  if (spot.kind === "wiki") {
    text = item.ref + (spot.closed ? "" : "]]");
    changes.push({ from, to, insert: text });
    const next = view.state.sliceDoc(to, to + 2);
    caretAfter = from + text.length + (spot.closed && next === "]]" ? 2 : 0);
  } else {
    text = `/${item.ref}.md${spot.closed ? "" : ")"}`;
    let shift = 0;
    if (spot.emptyText) {
      const title = item.title.replace(/([[\]])/g, "\\$1");
      changes.push({ from: from - 2, insert: title });
      shift = title.length;
    }
    changes.push({ from, to, insert: text });
    caretAfter = from + shift + text.length + (spot.closed ? 1 : 0);
  }
  view.dispatch({ changes, selection: { anchor: caretAfter }, userEvent: "input.complete" });
}

async function source(context) {
  const spot = spotAt(context.state, context.pos, context.explicit);
  if (!spot) return null;
  if (!items) await load();
  if (!items.length) return null;

  const current = spot.current ? resolve(spot.current) : null;
  const query = context.explicit ? "" : spot.query;
  const list = rank(query, current);
  if (!list.length) return null;

  return {
    from: spot.from,
    to: spot.to,
    filter: false,
    options: list.map((it) => option(it, spot)),
  };
}

const draftLabel = {
  render(completion) {
    if (!completion.draft) return null;
    const el = document.createElement("span");
    el.className = "roe-link-draft";
    el.textContent = "DRAFT";
    return el;
  },
  position: 90,
};

// Clicking an internal link opens the list for it.
const openOnClick = EditorView.updateListener.of((update) => {
  if (!update.selectionSet) return;
  if (!update.transactions.some((tr) => tr.isUserEvent("select.pointer"))) return;
  const sel = update.state.selection.main;
  if (!sel.empty || !spotAt(update.state, sel.head, true)) return;
  setTimeout(() => startCompletion(update.view), 0);
});

export function internalLinks() {
  load();
  return [
    autocompletion({
      override: [source],
      icons: false,
      addToOptions: [draftLabel],
      tooltipClass: () => "roe-link-picker",
      maxRenderedOptions: 100,
    }),
    openOnClick,
  ];
}

// ── Drawing wikilinks ─────────────────────────────────────────────────────

const syntaxMark = Decoration.mark({ class: "roe-md-wiki-syntax" });
const linkMark = Decoration.mark({ class: "roe-md-link-text" });
const missingMark = Decoration.mark({ class: "roe-md-link-text roe-md-wiki-missing" });
const hide = Decoration.replace({});

class TitleWidget extends WidgetType {
  constructor(text, missing) {
    super();
    this.text = text;
    this.missing = missing;
  }
  eq(other) {
    return other.text === this.text && other.missing === this.missing;
  }
  toDOM() {
    const el = document.createElement("span");
    el.className = `roe-md-link-text${this.missing ? " roe-md-wiki-missing" : ""}`;
    el.textContent = this.text;
    return el;
  }
  ignoreEvent() {
    return false;
  }
}

function inCode(state, pos) {
  for (let node = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (/^(InlineCode|FencedCode|CodeBlock|CodeText|HTMLBlock)$/.test(node.name)) return true;
  }
  return false;
}

function buildWikilinks(view, live) {
  const { state } = view;
  const decos = [];
  const sel = state.selection.ranges;
  for (const { from, to } of view.visibleRanges) {
    const text = state.doc.sliceString(from, to);
    for (const m of text.matchAll(WIKI)) {
      const start = from + m.index;
      const end = start + m[0].length;
      if (!m[1].trim() || inCode(state, start)) continue;
      const item = resolve(m[1]);
      const missing = item === null; // undefined: the list hasn't loaded
      const targetFrom = start + 2;
      const targetTo = targetFrom + m[1].length;
      const label = m[2] ? m[2].slice(1) : "";
      const active = sel.some((r) => r.from <= end && r.to >= start);

      if (live && !active) {
        if (label.trim()) {
          decos.push(hide.range(start, targetTo + 1));
          decos.push((missing ? missingMark : linkMark).range(targetTo + 1, end - 2));
          decos.push(hide.range(end - 2, end));
        } else {
          const shown = item?.title || m[1].trim();
          decos.push(Decoration.replace({ widget: new TitleWidget(shown, missing) }).range(start, end));
        }
        continue;
      }

      decos.push(syntaxMark.range(start, targetFrom));
      if (label) {
        decos.push(syntaxMark.range(targetFrom, targetTo + 1));
        if (label.length) decos.push((missing ? missingMark : linkMark).range(targetTo + 1, end - 2));
      } else {
        decos.push((missing ? missingMark : linkMark).range(targetFrom, targetTo));
      }
      decos.push(syntaxMark.range(end - 2, end));
    }
  }
  return Decoration.set(decos, true);
}

export function wikilinks(mode) {
  const live = mode === "live";
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        views.add(view);
        this.decorations = buildWikilinks(view, live);
      }
      update(update) {
        const reloaded = update.transactions.some((tr) => tr.effects.some((e) => e.is(listLoaded)));
        if (update.docChanged || update.viewportChanged || reloaded || (live && update.selectionSet)) {
          this.decorations = buildWikilinks(update.view, live);
        }
      }
    },
    { decorations: (plugin) => plugin.decorations },
  );
}

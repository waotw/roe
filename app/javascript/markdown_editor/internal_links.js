// Links to the site's own posts, pages, products and docs, in the content
// editor. The list itself, and what counts as a link, is link_targets.js.
//
// A list of them opens:
//   - after `](/` in a Markdown link: picking one writes `/posts/x.md)`,
//     and fills in the link text with the title when the brackets are empty;
//   - after `[[`: picking one writes `posts/x]]`;
//   - on clicking where an existing link's target is written — inside the
//     () of a link to this site, old style (`/posts/lab-full`) or new, or
//     between [[ and | — so it can be pointed somewhere else.
// Never on a link's text, and never for a link to another site: after the
// LINK button or ⌘K, typing / in the () is what opens it.
//
// Wikilinks are also drawn here: in SOURCE as written, coloured; in LIVE as
// the link alone (its text, or the item's title), with the brackets back
// when the caret is on it. One that names no file is red.

import { autocompletion, startCompletion } from "@codemirror/autocomplete";
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view";
import { StateEffect } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { load, loaded, onLoad, resolve, spotIn, rank, detail, edits, WIKI } from "markdown_editor/link_targets";

const views = new Set();
const listLoaded = StateEffect.define();

onLoad(() => {
  for (const view of views) {
    if (view.dom.isConnected) view.dispatch({ effects: listLoaded.of(null) });
    else views.delete(view);
  }
});

// The spot, with the line it's on (its offsets are within that line).
function spotAt(state, pos, explicit) {
  const line = state.doc.lineAt(pos);
  const spot = spotIn(line.text, pos - line.from, explicit);
  return spot ? { ...spot, line } : null;
}

// ── The completion source ─────────────────────────────────────────────────

function option(item, spot) {
  return {
    label: `${item.title} ${item.path}`,
    displayLabel: item.title,
    detail: detail(item),
    draft: item.draft,
    apply: (view) => {
      const { line } = spot;
      const { changes, caret } = edits(item, spot, line.text.slice(spot.to));
      view.dispatch({
        changes: changes.map((c) => ({ from: line.from + c.from, to: line.from + c.to, insert: c.insert })),
        selection: { anchor: line.from + caret },
        userEvent: "input.complete",
      });
    },
  };
}

async function source(context) {
  const spot = spotAt(context.state, context.pos, context.explicit);
  if (!spot) return null;
  if (!loaded()) await load();

  const current = spot.current ? resolve(spot.current) : null;
  // Just clicked: the whole list, current target first. Typing narrows it.
  const query = context.explicit && clickedAt.get(context.view) === spot.query ? "" : spot.query;
  const list = rank(query, current);
  if (!list.length) return null;

  return {
    from: spot.line.from + spot.from,
    to: spot.line.from + spot.to,
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

// What was before the caret in the link when it was clicked.
const clickedAt = new WeakMap();

// Clicking where a link's target is written opens the list for it.
const openOnClick = EditorView.updateListener.of((update) => {
  const { view } = update;
  const sel = update.state.selection.main;
  const clicked = update.transactions.some((tr) => tr.isUserEvent("select.pointer"));
  const spot = clicked && sel.empty ? spotAt(update.state, sel.head, true) : null;
  if (spot) {
    clickedAt.set(view, spot.query);
    setTimeout(() => startCompletion(view), 0);
  }
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
      if (m[2]) {
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

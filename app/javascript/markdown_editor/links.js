// Which [brackets] are links.
//
// The grammar (@lezer/markdown) calls every `[text]` a Link, because CommonMark
// can't know without the reference definitions whether `[text]` points
// anywhere. kramdown does know: `[text]` and `[text][id]` are links only when a
// `[text]: url` / `[id]: url` definition exists in the document; otherwise they
// render as the plain text they are, brackets and all. So the editor asks the
// same question before drawing anything as a link.
//
// Used by both modes: linkStyles colours real links (the highlight style no
// longer does — it would colour every bracket pair), and live_preview.js only
// hides brackets around real links.

import { Decoration, ViewPlugin } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";

// `[label]: url` at the start of a line (up to 3 spaces in). `[^1]:` is a
// footnote, not a link definition.
const DEFINITION = /^ {0,3}\[([^\]^][^\]]*)\]:/gm;

// kramdown matches labels ignoring case and runs of whitespace.
const normalize = (label) => label.trim().replace(/\s+/g, " ").toLowerCase();

const definitionCache = new WeakMap();

// The set of defined labels, worked out once per document version.
export function linkDefinitions(state) {
  const doc = state.doc;
  let labels = definitionCache.get(doc);
  if (!labels) {
    labels = new Set();
    for (const match of doc.toString().matchAll(DEFINITION)) {
      labels.add(normalize(match[1]));
    }
    definitionCache.set(doc, labels);
  }
  return labels;
}

// Is this Link (or Image) node something kramdown will render as a link?
//   [text](url)        yes, always
//   [text][id]         if `id` is defined
//   [text][] / [text]  if `text` is defined
export function isRealLink(state, node) {
  if (node.getChild("URL")) return true;
  const marks = node.getChildren("LinkMark");
  const close = marks.find((m) => state.doc.sliceString(m.from, m.to) === "]");
  if (!close) return false;
  const label = node.getChild("LinkLabel");
  const textStart = node.name === "Image" ? node.from + 2 : node.from + 1;
  let name = label ? state.doc.sliceString(label.from + 1, label.to - 1) : "";
  if (!name.trim()) name = state.doc.sliceString(textStart, close.from);
  return linkDefinitions(state).has(normalize(name));
}

const linkMark = Decoration.mark({ class: "roe-md-link" });
const plainBracket = Decoration.mark({ class: "roe-md-bracket" });

function buildLinkMarks(view) {
  const { state } = view;
  const decos = [];
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter(node) {
        if (node.name !== "Link" && node.name !== "Image") return;
        if (isRealLink(state, node.node)) {
          decos.push(linkMark.range(node.from, node.to));
        } else {
          // Not a link: its brackets are ordinary characters, drawn in the
          // body colour rather than the grey of markdown markers.
          for (const mark of node.node.getChildren("LinkMark")) {
            decos.push(plainBracket.range(mark.from, mark.to));
          }
        }
        return false;
      },
    });
  }
  return Decoration.set(decos, true);
}

export const linkStyles = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildLinkMarks(view);
    }
    update(update) {
      if (
        update.docChanged ||
        update.viewportChanged ||
        syntaxTree(update.startState) !== syntaxTree(update.state)
      ) {
        this.decorations = buildLinkMarks(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

// Obsidian-style live preview.
//
// The document is always the markdown file, byte for byte. This module only
// changes how those characters are DRAWN: markers are hidden, or swapped for
// something that looks like the rendered result, and they come back the
// moment the caret touches the element they belong to.
//
// "Touches" is per element, not per line. With the caret inside **bold**, its
// asterisks show; a link two words over on the same line stays rendered. Block
// markers (# for headings, > for quotes, - for bullets) are per line, because a
// heading or a quote line IS the element.
//
// Roe-anji blocks (```collection and friends) are not handled here — they need
// block-level replacement, which CodeMirror only allows from a state field.
// See roe_blocks.js. This plugin leaves their lines alone.

import { Decoration, ViewPlugin, WidgetType } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import { ROE_BLOCK_KINDS, fenceKind, autoGalleryLines } from "markdown_editor/roe_blocks";

const hide = Decoration.replace({});
const markText = Decoration.mark({ class: "roe-md-mark" });
const linkText = Decoration.mark({ class: "roe-md-link-text" });

const lineClass = (cls) => Decoration.line({ class: cls });
const HEADING_LINES = [1, 2, 3, 4, 5, 6].map((n) => lineClass(`roe-md-h${n}`));
const QUOTE_LINE = lineClass("roe-md-quote");
const HR_LINE = lineClass("roe-md-hr");
const CODE_LINE = lineClass("roe-md-codeblock");
const CODE_FENCE_LINE = lineClass("roe-md-codeblock roe-md-fence");
const POETRY_LINE = lineClass("roe-md-poetry");
const TABLE_LINE = lineClass("roe-md-table");
const HTML_LINE = lineClass("roe-md-htmlblock");

const MARK_OPEN = /^<mark(\s[^>]*)?>$/i;
const MARK_CLOSE = /^<\/mark\s*>$/i;

class BulletWidget extends WidgetType {
  eq() {
    return true;
  }
  toDOM() {
    const span = document.createElement("span");
    span.className = "roe-md-bullet";
    span.textContent = "•";
    return span;
  }
}

class ImageWidget extends WidgetType {
  constructor(src, alt) {
    super();
    this.src = src;
    this.alt = alt;
  }
  eq(other) {
    return other.src === this.src && other.alt === this.alt;
  }
  toDOM() {
    const wrap = document.createElement("span");
    wrap.className = "roe-md-image";
    const img = document.createElement("img");
    img.src = this.src;
    img.alt = this.alt;
    img.loading = "lazy";
    // A broken path shows as its alt text rather than a broken-image icon, so
    // the writer still sees which image the line points at.
    img.onerror = () => {
      wrap.textContent = `🖼 ${this.alt || this.src}`;
      wrap.classList.add("roe-md-image-missing");
    };
    wrap.appendChild(img);
    return wrap;
  }
  // Clicks land in the editor, which moves the caret onto the image and so
  // reveals its markdown.
  ignoreEvent() {
    return false;
  }
}

const bullet = Decoration.replace({ widget: new BulletWidget() });

// Does any selection range touch [from, to]? Inclusive at both ends, so the
// caret sitting right after `**bold**` still counts as inside it.
function touches(ranges, from, to) {
  for (const r of ranges) if (r.from <= to && r.to >= from) return true;
  return false;
}

function lineTouched(state, ranges, pos) {
  const line = state.doc.lineAt(pos);
  return touches(ranges, line.from, line.to);
}

function eachLine(state, from, to, fn) {
  let pos = from;
  while (pos <= to) {
    const line = state.doc.lineAt(pos);
    fn(line);
    pos = line.to + 1;
  }
}

function hideWithTrailingSpace(state, decos, from, to) {
  const next = state.doc.sliceString(to, to + 1);
  decos.push(hide.range(from, next === " " ? to + 1 : to));
}

function buildDecorations(view) {
  const { state } = view;
  const ranges = state.selection.ranges;
  const decos = [];
  const htmlTags = [];

  // Automatic galleries: closed, roe_blocks.js draws the card; open, the
  // lines get the same look as an open ```gallery.
  const galleryLines = autoGalleryLines(state);
  for (const n of galleryLines) {
    const line = state.doc.line(n);
    if (line.from >= view.viewport.from && line.from <= view.viewport.to) {
      decos.push(CODE_LINE.range(line.from));
    }
  }

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from,
      to,
      enter(node) {
        const name = node.name;

        // ── Roe-anji blocks: owned by roe_blocks.js ───────────────────
        if (name === "FencedCode") {
          const kind = fenceKind(state, node.node);
          if (ROE_BLOCK_KINDS.has(kind)) {
            // Shown as code when the caret is inside (the card is gone).
            if (touches(ranges, node.from, node.to)) {
              eachLine(state, node.from, node.to, (line) =>
                decos.push(CODE_LINE.range(line.from)),
              );
            }
            return false;
          }
          const fenceLines = new Set([
            state.doc.lineAt(node.from).number,
            state.doc.lineAt(node.to).number,
          ]);
          eachLine(state, node.from, node.to, (line) => {
            const fence = fenceLines.has(line.number);
            if (kind === "poetry") {
              decos.push((fence ? CODE_FENCE_LINE : POETRY_LINE).range(line.from));
            } else {
              decos.push((fence ? CODE_FENCE_LINE : CODE_LINE).range(line.from));
            }
          });
          return false;
        }

        if (name === "CodeBlock") {
          eachLine(state, node.from, node.to, (line) =>
            decos.push(CODE_LINE.range(line.from)),
          );
          return false;
        }

        if (name === "HTMLBlock" || name === "CommentBlock") {
          eachLine(state, node.from, node.to, (line) =>
            decos.push(HTML_LINE.range(line.from)),
          );
          return false;
        }

        if (name === "Table") {
          eachLine(state, node.from, node.to, (line) =>
            decos.push(TABLE_LINE.range(line.from)),
          );
          return false;
        }

        // ── Block markers: revealed per line ──────────────────────────
        const heading = /^(?:ATX|Setext)Heading(\d)$/.exec(name);
        if (heading) {
          const level = Number(heading[1]);
          decos.push(HEADING_LINES[level - 1].range(state.doc.lineAt(node.from).from));
          if (!touches(ranges, node.from, node.to) && name.startsWith("ATX")) {
            const marks = node.node.getChildren("HeaderMark");
            for (const mark of marks) {
              if (mark.from === node.from) {
                hideWithTrailingSpace(state, decos, mark.from, mark.to);
              } else if (mark.to === node.to) {
                // Closing hashes: `## Title ##` — drop them and the space
                // before them.
                const prev = state.doc.sliceString(mark.from - 1, mark.from);
                decos.push(hide.range(prev === " " ? mark.from - 1 : mark.from, mark.to));
              }
            }
          }
          return;
        }

        if (name === "Blockquote") {
          eachLine(state, node.from, node.to, (line) =>
            decos.push(QUOTE_LINE.range(line.from)),
          );
          return;
        }

        if (name === "QuoteMark") {
          if (!lineTouched(state, ranges, node.from)) {
            hideWithTrailingSpace(state, decos, node.from, node.to);
          }
          return;
        }

        if (name === "ListMark") {
          const list = node.node.parent?.parent;
          if (list?.name === "BulletList" && !lineTouched(state, ranges, node.from)) {
            decos.push(bullet.range(node.from, node.to));
          }
          return;
        }

        if (name === "HorizontalRule") {
          if (!lineTouched(state, ranges, node.from)) {
            decos.push(HR_LINE.range(state.doc.lineAt(node.from).from));
            decos.push(hide.range(node.from, node.to));
          }
          return;
        }

        // ── Inline elements: revealed per element ─────────────────────
        const active = touches(ranges, node.from, node.to);

        switch (name) {
          case "StrongEmphasis":
          case "Emphasis":
          case "Strikethrough":
          case "Highlight":
          case "Aside":
          case "InlineCode":
            if (!active) {
              const markName = {
                StrongEmphasis: "EmphasisMark",
                Emphasis: "EmphasisMark",
                Strikethrough: "StrikethroughMark",
                Highlight: "HighlightMark",
                Aside: "AsideMark",
                InlineCode: "CodeMark",
              }[name];
              for (const mark of node.node.getChildren(markName)) {
                decos.push(hide.range(mark.from, mark.to));
              }
            }
            // Nested emphasis (***both***, **bold _and_ italic**) needs the
            // walk to continue; code spans have nothing inside worth seeing.
            return name !== "InlineCode";

          case "Link": {
            const marks = node.node.getChildren("LinkMark");
            const close = marks.find(
              (m) => state.doc.sliceString(m.from, m.to) === "]",
            );
            if (close && marks[0]?.from === node.from) {
              decos.push(linkText.range(node.from + 1, close.from));
              if (!active) {
                decos.push(hide.range(node.from, node.from + 1));
                decos.push(hide.range(close.from, node.to));
              }
            }
            return;
          }

          case "Image": {
            // Inside an open automatic gallery: show the line as written, like
            // an open ```gallery, not as a column of inline images.
            if (galleryLines.has(state.doc.lineAt(node.from).number)) return false;
            if (!active) {
              const url = node.node.getChild("URL");
              const marks = node.node.getChildren("LinkMark");
              const close = marks.find(
                (m) => state.doc.sliceString(m.from, m.to) === "]",
              );
              if (url && close) {
                const src = state.doc.sliceString(url.from, url.to);
                const alt = state.doc.sliceString(node.from + 2, close.from);
                decos.push(
                  Decoration.replace({ widget: new ImageWidget(src, alt) }).range(
                    node.from,
                    node.to,
                  ),
                );
              }
            }
            return false;
          }

          case "FootnoteRef":
            if (!active) {
              for (const mark of node.node.getChildren("FootnoteMark")) {
                decos.push(hide.range(mark.from, mark.to));
              }
            }
            return false;

          case "Escape":
            if (!active) decos.push(hide.range(node.from, node.from + 1));
            return false;

          case "HTMLTag":
            htmlTags.push({
              from: node.from,
              to: node.to,
              text: state.doc.sliceString(node.from, node.to),
            });
            return false;
        }
      },
    });
  }

  // <mark>…</mark>: the highlight Roe has always written. Pair each opening
  // tag with the next closing one; the pair renders like ==text==.
  for (let i = 0; i < htmlTags.length; i++) {
    if (!MARK_OPEN.test(htmlTags[i].text)) continue;
    const open = htmlTags[i];
    const close = htmlTags.slice(i + 1).find((t) => MARK_CLOSE.test(t.text));
    if (!close) continue;
    if (close.from > open.to) decos.push(markText.range(open.to, close.from));
    if (!touches(ranges, open.from, close.to)) {
      decos.push(hide.range(open.from, open.to));
      decos.push(hide.range(close.from, close.to));
    }
  }

  return Decoration.set(decos, true);
}

export const livePreview = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildDecorations(view);
    }
    update(update) {
      if (
        update.docChanged ||
        update.selectionSet ||
        update.viewportChanged ||
        syntaxTree(update.startState) !== syntaxTree(update.state)
      ) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

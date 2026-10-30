// The markdown grammar the live editor reads.
//
// This only decides what the EDITOR shows. Rendering is still kramdown plus
// HasMarkdownExtensions on the server, and nothing here is sent anywhere — the
// file stays exactly the text that was typed. So a mismatch between this
// grammar and kramdown costs a wrong-looking line in the editor, never a wrong
// page. The markdown check (MarkdownDoctor) remains the authority on whether
// something will render the way it looks.
//
// The base is CommonMark (@lezer/markdown) plus GFM strikethrough and tables,
// which kramdown also supports. On top of that, Roe's own syntax:
//
//   ==text==       highlight, rendered as <mark> (process_highlights)
//   [^1] / [^1]:   kramdown footnotes, including the 4-space continuation lines
//                  that would otherwise read as an indented code block
//   ||text||       pullquote split markers
//
// Roe-anji blocks (```collection and friends) need nothing here: they are
// ordinary fenced code to the grammar, and roe_blocks.js reads the word after
// the fence.

import {
  Language,
  LanguageSupport,
  HighlightStyle,
  defineLanguageFacet,
  languageDataProp,
} from "@codemirror/language";
import { parser as commonmark, Strikethrough, Table } from "@lezer/markdown";
import { Tag, tags, styleTags } from "@lezer/highlight";

export const highlightTag = Tag.define();
export const asideTag = Tag.define();
export const footnoteTag = Tag.define();

const EQUALS = 61;
const PIPE = 124;
const BRACKET_OPEN = 91;
const BRACKET_CLOSE = 93;
const CARET = 94;
const BACKSLASH = 92;

const isSpace = (text) => /\s|^$/.test(text);

// ==text==. Mirrors HasMarkdownExtensions::HIGHLIGHT_PATTERN: the pair has to
// hug its text (`a == b` is a comparison), and a run of three or more `=` is
// never a marker, so setext heading underlines are left alone.
const HighlightDelim = { resolve: "Highlight", mark: "HighlightMark" };
const Highlight = {
  defineNodes: [
    { name: "Highlight", style: { "Highlight/...": highlightTag } },
    { name: "HighlightMark", style: tags.processingInstruction },
  ],
  parseInline: [
    {
      name: "Highlight",
      parse(cx, next, pos) {
        if (next != EQUALS || cx.char(pos + 1) != EQUALS) return -1;
        if (cx.char(pos + 2) == EQUALS || cx.char(pos - 1) == EQUALS) return -1;
        if (cx.char(pos - 1) == BACKSLASH) return -1;
        const before = cx.slice(pos - 1, pos);
        const after = cx.slice(pos + 2, pos + 3);
        return cx.addDelimiter(
          HighlightDelim,
          pos,
          pos + 2,
          !isSpace(after),
          !isSpace(before),
        );
      },
      after: "Emphasis",
    },
  ],
};

// ||text|| — the pullquote split. The server swaps every `||` for a token
// before kramdown runs, so they never collide with tables; here a table row's
// pipes are consumed by the Table extension before inline parsing sees them.
const AsideDelim = { resolve: "Aside", mark: "AsideMark" };
const PullquoteSplit = {
  defineNodes: [
    { name: "Aside", style: { "Aside/...": asideTag } },
    { name: "AsideMark", style: tags.processingInstruction },
  ],
  parseInline: [
    {
      name: "Aside",
      parse(cx, next, pos) {
        if (next != PIPE || cx.char(pos + 1) != PIPE) return -1;
        if (cx.char(pos + 2) == PIPE || cx.char(pos - 1) == PIPE) return -1;
        const before = cx.slice(pos - 1, pos);
        const after = cx.slice(pos + 2, pos + 3);
        return cx.addDelimiter(
          AsideDelim,
          pos,
          pos + 2,
          !isSpace(after),
          !isSpace(before),
        );
      },
      after: "Emphasis",
    },
  ],
};

// kramdown footnotes. A definition is a container like a list item: the first
// line starts with `[^label]:`, and it continues over lines indented four
// spaces — the indent editor_controller's footnote Enter handling writes, and
// the one kramdown requires. Without this, every continuation paragraph would
// parse as an indented code block and show in monospace.
const FOOTNOTE_START = /^\[\^([^\]\s]+)\]:/;
const Footnotes = {
  defineNodes: [
    {
      name: "FootnoteDefinition",
      block: true,
      composite(cx, line, value) {
        if (line.indent < line.baseIndent + value && line.next > -1) return false;
        line.moveBaseColumn(line.baseIndent + value);
        return true;
      },
    },
    { name: "FootnoteLabel", style: tags.labelName },
    { name: "FootnoteRef", style: footnoteTag },
    { name: "FootnoteMark", style: tags.processingInstruction },
  ],
  parseBlock: [
    {
      name: "FootnoteDefinition",
      before: "Blockquote",
      parse(cx, line) {
        if (line.next != BRACKET_OPEN) return false;
        const match = FOOTNOTE_START.exec(line.text.slice(line.pos));
        if (!match) return false;

        const labelFrom = cx.lineStart + line.pos;
        cx.startComposite("FootnoteDefinition", line.pos, 4);
        cx.addElement(
          cx.elt("FootnoteLabel", labelFrom, labelFrom + match[0].length),
        );
        let contentStart = line.pos + match[0].length;
        while (/[ \t]/.test(line.text.charAt(contentStart))) contentStart++;
        line.moveBase(contentStart);
        return null;
      },
    },
  ],
  parseInline: [
    {
      name: "FootnoteRef",
      parse(cx, next, pos) {
        if (next != BRACKET_OPEN || cx.char(pos + 1) != CARET) return -1;
        let end = pos + 2;
        while (end < cx.end) {
          const ch = cx.char(end);
          if (ch == BRACKET_CLOSE || ch == 32 || ch == 9 || ch == 10) break;
          end++;
        }
        if (end == pos + 2 || cx.char(end) != BRACKET_CLOSE) return -1;
        return cx.addElement(
          cx.elt("FootnoteRef", pos, end + 1, [
            cx.elt("FootnoteMark", pos, pos + 2),
            cx.elt("FootnoteMark", end, end + 1),
          ]),
        );
      },
      before: "Link",
    },
  ],
};

const data = defineLanguageFacet({
  commentTokens: { block: { open: "<!--", close: "-->" } },
});

const parser = commonmark.configure([
  Strikethrough,
  Table,
  Highlight,
  PullquoteSplit,
  Footnotes,
  {
    props: [
      languageDataProp.add({ Document: data }),
      styleTags({ "HTMLTag HTMLBlock": tags.processingInstruction }),
    ],
  },
]);

export const markdownLanguage = new Language(data, parser, [], "markdown");
export const markdown = () => new LanguageSupport(markdownLanguage);

// Class names, not colours: the look lives in application.css under
// MARKDOWN EDITOR, where it can be changed without touching JavaScript. The
// same classes serve both modes; the editor carries roe-md-live or
// roe-md-source and the stylesheet decides what each one looks like.
export const roeHighlightStyle = HighlightStyle.define([
  { tag: tags.heading1, class: "roe-md-heading" },
  { tag: tags.heading2, class: "roe-md-heading" },
  { tag: tags.heading3, class: "roe-md-heading" },
  { tag: tags.heading4, class: "roe-md-heading" },
  { tag: tags.heading5, class: "roe-md-heading" },
  { tag: tags.heading6, class: "roe-md-heading" },
  { tag: tags.strong, class: "roe-md-strong" },
  { tag: tags.emphasis, class: "roe-md-em" },
  { tag: tags.strikethrough, class: "roe-md-strike" },
  { tag: highlightTag, class: "roe-md-mark" },
  { tag: asideTag, class: "roe-md-aside" },
  { tag: footnoteTag, class: "roe-md-fnref" },
  // No tags.link: the grammar calls every [bracket pair] a link, and most
  // aren't. links.js colours only the ones kramdown will link.
  { tag: tags.url, class: "roe-md-url" },
  { tag: tags.monospace, class: "roe-md-code" },
  { tag: tags.quote, class: "roe-md-quote-text" },
  { tag: tags.labelName, class: "roe-md-label" },
  { tag: tags.processingInstruction, class: "roe-md-syntax" },
  { tag: tags.contentSeparator, class: "roe-md-syntax" },
  { tag: tags.comment, class: "roe-md-comment" },
]);

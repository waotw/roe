// Footnotes in the live editor.
//
// kramdown keeps a footnote's text inside the note only while every line after
// the first is indented four spaces:
//
//   [^1]: The first paragraph.
//
//       A second paragraph, still in the note.
//
//       ```gallery
//       ![a](/media/images/a.jpg)
//       ```
//
// One line indented three spaces, or a paste that arrives flush left, and
// everything from there on falls out of the note into the body — or below the
// footnotes list entirely. Nothing about that is visible while writing, so the
// editor keeps the indent for the writer:
//
//   - Paste: lines pasted into a note get the four spaces, so a quote copied
//     from another page lands inside the note it was meant for.
//   - "Am I in a footnote?" is answered by the syntax tree (syntax.js parses
//     footnote definitions the same way kramdown does), not by scanning text,
//     so `[^sink]:` labels count as well as `[^1]:`.
//
// Enter keeps going through editor_controller's handleFootnoteEnter, which
// asks footnoteContinuation() here first when the live editor is running.

import { EditorView } from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";

export const FOOTNOTE_INDENT = "    ";
const LABEL = /^\[\^([^\]\s]+)\]:/;

// The footnote definition the position is in: { label, from, to, line } or
// null. `line` is the definition's first line. A position on a blank line
// inside a note — between two of its paragraphs — counts as inside it, as
// long as an indented line follows (that's what keeps the note going).
export function footnoteAt(state, pos) {
  let node = syntaxTree(state).resolveInner(pos, -1);
  for (; node; node = node.parent) {
    if (node.name === "FootnoteDefinition") {
      const line = state.doc.lineAt(node.from);
      const match = LABEL.exec(line.text);
      return { label: match?.[1] ?? "", from: node.from, to: node.to, line };
    }
  }

  // The tree ends a note at its last non-blank line, so a caret on a blank
  // line just after a paragraph isn't inside it by the tree's account. Walk
  // up: blank lines, then indented lines, then the definition line means the
  // caret is in the note's space.
  const here = state.doc.lineAt(pos);
  if (here.text.trim() !== "" && !/^ {4}/.test(here.text)) return null;
  for (let n = here.number - 1; n >= 1; n--) {
    const text = state.doc.line(n).text;
    if (LABEL.test(text)) {
      const line = state.doc.line(n);
      return { label: LABEL.exec(text)[1], from: line.from, to: here.to, line };
    }
    if (text.trim() === "" || /^ {4}/.test(text)) continue;
    return null;
  }
  return null;
}

// What a new line at `pos` needs in front of it to stay in the note: four
// spaces, plus `> ` when the line being continued is a quote inside the note.
// null when the position isn't in a footnote.
export function footnoteContinuation(state, pos) {
  const note = footnoteAt(state, pos);
  if (!note) return null;
  const line = state.doc.lineAt(pos);
  const body = line.number === note.line.number
    ? line.text.replace(LABEL, "").replace(/^\s*/, "")
    : line.text.replace(/^ {0,4}/, "");
  return FOOTNOTE_INDENT + (/^>(\s|$)/.test(body) ? "> " : "");
}

// Indent every line after the first. The first line goes where the caret is,
// which already has its indent (or is the definition line itself).
export function indentForNote(text) {
  return text
    .split("\n")
    .map((line, i) => (i === 0 || line.trim() === "" || line.startsWith(FOOTNOTE_INDENT) ? line : FOOTNOTE_INDENT + line))
    .join("\n");
}

// Plain-text pastes of more than one line into a note get the indent. Single
// lines go straight in — they land on the line the caret's already on. Rich
// pastes still arrive as plain text: the editor only ever holds markdown.
export const footnotePaste = EditorView.domEventHandlers({
  paste(event, view) {
    const text = event.clipboardData?.getData("text/plain");
    if (!text || !text.includes("\n")) return false;

    const { state } = view;
    const range = state.selection.main;
    if (!footnoteAt(state, range.from)) return false;

    const insert = indentForNote(text.replace(/\r\n?/g, "\n"));
    if (insert === text) return false;

    event.preventDefault();
    view.dispatch({
      changes: { from: range.from, to: range.to, insert },
      selection: { anchor: range.from + insert.length },
      scrollIntoView: true,
      userEvent: "input.paste",
    });
    return true;
  },
});

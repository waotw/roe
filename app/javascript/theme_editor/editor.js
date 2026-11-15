// The theme editor's CodeMirror 6 setup: CSS colouring, line numbers, undo,
// find and replace, and the highlighted rules INSPECT shows.
//
// The <textarea> stays in the form, hidden, and is kept in step with the
// editor on every change, so a plain form post still sends exactly the text
// in the editor.

import { EditorState, StateField, StateEffect, RangeSetBuilder } from "@codemirror/state";
import {
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLine,
  highlightActiveLineGutter,
  drawSelection,
  highlightSpecialChars,
  Decoration,
} from "@codemirror/view";
import { history, historyKeymap, defaultKeymap, indentWithTab } from "@codemirror/commands";
import {
  syntaxHighlighting,
  defaultHighlightStyle,
  bracketMatching,
  indentOnInput,
  indentUnit,
} from "@codemirror/language";
import { search, searchKeymap, highlightSelectionMatches, openSearchPanel } from "@codemirror/search";
import { css } from "@codemirror/lang-css";

// ── Rules INSPECT found ───────────────────────────────────────────────────
//
// setInspectRanges([{ from, to, kind }]) marks whole lines: "current" for the
// rule PREV / NEXT is on, "match" for the other matches, "dim" for a match
// inside an @media block this preview doesn't meet. An empty list clears.

export const setInspectRanges = StateEffect.define();

const lineClass = {
  current: Decoration.line({ class: "te-rule-current" }),
  match: Decoration.line({ class: "te-rule-match" }),
  dim: Decoration.line({ class: "te-rule-dim" }),
};

const inspectField = StateField.define({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes);
    for (const e of tr.effects) {
      if (!e.is(setInspectRanges)) continue;
      const byLine = new Map();
      const rank = { dim: 0, match: 1, current: 2 };
      for (const r of e.value) {
        const first = tr.state.doc.lineAt(r.from).number;
        const last = tr.state.doc.lineAt(Math.max(r.from, r.to - 1)).number;
        for (let n = first; n <= last; n++) {
          const had = byLine.get(n);
          if (!had || rank[r.kind] > rank[had]) byLine.set(n, r.kind);
        }
      }
      const builder = new RangeSetBuilder();
      for (const n of [...byLine.keys()].sort((a, b) => a - b)) {
        builder.add(tr.state.doc.line(n).from, tr.state.doc.line(n).from, lineClass[byLine.get(n)]);
      }
      deco = builder.finish();
    }
    return deco;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// ── The editor ────────────────────────────────────────────────────────────

const look = EditorView.theme({
  "&": { height: "100%", fontSize: "13px", backgroundColor: "#fff" },
  ".cm-scroller": { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", lineHeight: "1.55" },
  ".cm-gutters": { backgroundColor: "#fff", color: "#9ca3af", borderRight: "0" },
  ".cm-activeLine": { backgroundColor: "#f8fafc" },
  ".cm-activeLineGutter": { backgroundColor: "#f1f5f9" },
  "&.cm-focused": { outline: "none" },
});

// Builds the editor in `parent`, replacing the textarea. `onChange(text)`
// runs after every edit; `onSave()` on ⌘S / Ctrl-S.
export function createEditor({ parent, textarea, onChange, onSave }) {
  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc: textarea.value,
      extensions: [
        lineNumbers(),
        highlightActiveLineGutter(),
        highlightSpecialChars(),
        history(),
        drawSelection(),
        indentOnInput(),
        indentUnit.of("  "),
        EditorState.tabSize.of(2),
        bracketMatching(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
        css(),
        search({ top: true }),
        EditorView.lineWrapping,
        inspectField,
        look,
        EditorView.editorAttributes.of({ class: "te-editor" }),
        keymap.of([
          { key: "Mod-s", preventDefault: true, run: () => { onSave(); return true; } },
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
          indentWithTab,
        ]),
        EditorView.updateListener.of((update) => {
          if (!update.docChanged) return;
          const text = update.state.doc.toString();
          textarea.value = text;
          onChange(text);
        }),
      ],
    }),
  });
  textarea.hidden = true;
  return view;
}

export function openFind(view) {
  openSearchPanel(view);
}

// Puts `from`–`to` in view about a third of the way down, and optionally
// selects it.
export function revealRange(view, from, to = from, { select = false, top = false } = {}) {
  const effects = EditorView.scrollIntoView(from, { y: top ? "start" : "center", yMargin: top ? 4 : 60 });
  view.dispatch({ effects, ...(select ? { selection: { anchor: from, head: to } } : {}) });
}

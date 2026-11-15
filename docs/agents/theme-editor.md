# The theme editor

Status: **built for 0.5.0.** Admin → Themes → EDIT CSS
(`admin/themes/edit`, layout `theme_editor`).

The design was settled in Figma before it was built: file "Roe-UI", page
"Theme editor — options", iteration 2 (`230:361`).

---

## Shape

- **Code:** CodeMirror 6 with `@codemirror/lang-css`. It replaced CodeMirror
  5, which was loaded as `window.CodeMirror` from `vendor/javascript/codemirror`
  and `vendor/stylesheets`; both folders are gone.
- **Preview:** beside the code in the same page, in an iframe. A separate
  preview tab was mocked and dropped.
- **Sections list:** read from the editor's text with the same one-line
  heading format `ThemeSections` reads in Ruby.
- **INSPECT:** reads rules from the editor's text, saved or not.

Four Stimulus controllers share `#theme-editor`. Each has one job, so no
controller grows past its own:

| Controller | Job |
|---|---|
| `css_editor` | The editor, background save, SAVE AS…, find |
| `theme_sections` | The SECTIONS list and its open / hidden / peek states |
| `theme_preview` | The iframe, the live CSS, the page menu, WIDE / PHONE, PREVIEW |
| `theme_inspector` | INSPECT: picking in the iframe, the results panel, the highlights |

They talk through events on the element: `css-editor:ready`,
`css-editor:change`, `css-editor:saved`, `theme-preview:load` and
`theme-preview:css`. The editor is also reachable as
`element.cssEditor` (`view`, `text()`, `reveal()`, `setInspectRanges()`).

`app/javascript/theme_editor/` holds the parts that don't touch Stimulus:

- `editor.js`: the CodeMirror setup and the line highlights.
- `css_rules.js`: rules, sections and variables from the text, using
  `@lezer/css`.
- `matching.js`: which rules match an element.

`css_rules.js` and `matching.js` import nothing but the parser, so they run in
Node and jsdom for testing (see the skill's markdown-editor notes for the
scratch setup).

## Decisions

- **The preview gets the CSS directly, not through a reload or a
  BroadcastChannel.** On each iframe load the theme's `<link>` is disabled
  and a `<style data-theme-editor>` holds the editor's text. Only the
  `/theme/` link is touched; fonts and Custom Code stay.
- **The preview keeps the editor's parameters.** `preview_theme` makes the
  first paint use this theme; `in_editor=1` makes a reference page leave out
  its own bar. A link clicked in the preview is followed with both added.
- **Matching is the browser's.** Each selector is tested with
  `element.matches()` on the picked element. The selector is not parsed for
  meaning.
  - States (`:hover`, `:focus`…) and pseudo-elements are taken off the top
    level first and shown as labels. Inside `:not()` or `:has()` they stay.
  - `@media` and `@supports` are tested with the iframe's `matchMedia` and
    `CSS.supports`. A rule that doesn't apply right now is dimmed, not
    hidden.
- **What it doesn't do:**
  - It doesn't work out which declaration wins the cascade. That is the hard
    part, and the card left it out of the first version.
  - It reads the theme file only, not Custom Code or font CSS.
  - "Inherited from" lists only inherited properties that neither the element
    nor a nearer ancestor sets.
- **SAVE AS…** (`themes#save_as`) writes the editor's text, not the saved
  file. It replaces the THEME INFO header with one that has the new name,
  Version 1.0.0, "Based on", and no fingerprint. The copy then reads as
  `:custom`, so updates never offer to replace it. It never activates the
  copy and never touches the original (conventions rule 8).
- **Saves never reload the page.** Cursor, scroll and undo survive, which is
  what "undo keeps working after you save" in the toolbar means.

## Traps

- The CodeMirror line highlights are line decorations; a rule's whole lines
  are marked. Rank `current` > `match` > `dim` when rules share a line.
- `bin/importmap pin` re-pins and re-downloads every shared dependency. When
  `@codemirror/lang-css` was added it bumped `@codemirror/view` and
  `@lezer/common` and dropped `preload: false` from existing pins. Restore
  `config/importmap.rb` and the changed `vendor/javascript` files, then add
  only the new pins.
- Removing `vendor/stylesheets` meant removing its line from
  `config/initializers/assets.rb`, which needs a server restart.

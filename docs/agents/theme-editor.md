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
| `css_editor` | The editor, background save, the unsaved-text draft, SAVE AS…, find |
| `theme_sections` | The SECTIONS list and its open / hidden / peek states |
| `theme_preview` | The iframe, the live CSS, the page menu, the width menu, PREVIEW, the splitter |
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
- **Other states** (`otherStateRules`): a rule that doesn't match now but
  would if its conditions held. Attribute tests and state pseudo-classes
  (`:checked`, `:open`, `:not(.class)`…) are taken out of every part of the
  selector, ancestors included; if what's left matches, the rule is listed in
  purple as `when <the conditions>`. `:has()`, `:empty` and the structural
  pseudo-classes aren't states, so rules using them are left out, or every
  paragraph would list `p:has(.site-logo)`. States written as classes
  (`.is-open`) aren't found; Roe's markup uses attributes.
- **Shift-click passes through.** While INSPECT is on, a shift-click is
  turned into a plain `el.click()` inside the real click, so the browser
  still counts it as the person's own and audio may start. A shift-click
  can't just be let through, because on a link it opens a new window. A
  MutationObserver on the picked element and its ancestors, ignoring
  `style` (a playing player rewrites it constantly), re-runs the match
  when the state changes from anywhere.
- **Preview widths:** full, three common widths (`COMMON` in the
  controller), and the theme's own breakpoints from its `min-width` and
  `max-width` queries (`breakpoints()`), read from the editor's text. A width
  wider than the pane is laid out at that width and scaled down with a
  transform, so `@media` rules see the real width.
- **Splitter:** the code and the preview share the width after the
  sections list as `--te-code` and `--te-preview`, in `fr` (`fr` can't go
  inside `calc()`, so it's two variables, not one ratio). The code's share
  is kept between 0.2 and 0.8, starts at 0.5, and is remembered in
  `localStorage`. While dragging, the iframe gets `pointer-events: none`,
  or it swallows the moves once the pointer crosses into it.
- **Menus close on any press outside them:** `pointerdown`, captured on the
  document, so presses CodeMirror handles itself count too. Presses inside
  the preview never reach the parent document, so `loaded()` adds a listener
  in the iframe, and a `blur` on the window covers the rest.
- **Draft:** the Markdown editor's pattern. Unsaved text goes to
  `localStorage` (`roe:theme-draft:<name>`) a second after typing stops and
  on `beforeunload`, with a fingerprint of the file it started from. It's
  offered back on the next visit, with a warning when the file has changed
  since. It's cleared on save, on SAVE AS…, on leaving with CANCEL or THEMES,
  and when undo brings the text back to the saved file.
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

- CodeMirror draws the selection on a layer behind the lines, so a line
  with a background (the active line, INSPECT's highlights) hid it
  completely. The layer is lifted above the text and multiplied, as in the
  Markdown editor. The selection (blue) and the other occurrences of the
  selected text (yellow) need different colours.

- The CodeMirror line highlights are line decorations; a rule's whole lines
  are marked. Rank `current` > `match` > `dim` when rules share a line.
- `bin/importmap pin` re-pins and re-downloads every shared dependency. When
  `@codemirror/lang-css` was added it bumped `@codemirror/view` and
  `@lezer/common` and dropped `preload: false` from existing pins. Restore
  `config/importmap.rb` and the changed `vendor/javascript` files, then add
  only the new pins.
- Removing `vendor/stylesheets` meant removing its line from
  `config/initializers/assets.rb`, which needs a server restart.

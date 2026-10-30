# Admin UI

The admin interface provides content editing, configuration, and site management.

## Admin Routes

| Path | Purpose |
|------|---------|
| `/admin` | Dashboard |
| `/admin/posts` | All posts |
| `/admin/posts/new` | Create post |
| `/admin/posts/:id/edit` | Edit post |
| `/admin/posts/:id/preview` | Live preview |
| `/admin/posts/:id/rename` | Rename post |
| `/admin/pages` | Pages management |
| `/admin/documentation` | Documentation |
| `/admin/medium/browse` | Media browser |
| `/admin/configs` | Configuration editor |
| `/admin/layouts` | Navigation/Footer editing |
| `/admin/settings` | Post template editor |
| `/admin/static_site` | Static generation controls |

## Editor Features

### Markdown Editor

The editor (`app/javascript/controllers/editor_controller.js`) provides:

- Auto-expanding textarea
- Live preview (Turbo frame)
- Table of contents generation
- Image/media insertion
- Card insertion (pullquotes, asides, post/product links)
- Collection insertion
- Action insertion — button (product/share/subscribe) and form (signup, paywall, …) blocks

### Live Markdown Editor (beta)

`editor.mode` in `content.yml` chooses between `live`, `source` and `textarea`. Unset means `textarea` while the editor is in beta. It's set from Settings → Content → Writing editor.

For `live` and `source`, `markdown_editor_controller.js` imports `app/javascript/markdown_editor/` and puts a CodeMirror 6 editor in place of `#content-textarea`. The CodeMirror modules are vendored and pinned `preload: false`, so no other page downloads them.

**The textarea is never replaced.** It stays in the form, hidden, and `editor.js` points its properties at the editor: `value`, `selectionStart`/`selectionEnd`, `setSelectionRange`, `setRangeText`, `focus`, and `document.execCommand("insertText")`. Its `input` events fire as they would for a real textarea. Enter and Tab are passed to the textarea's own keydown listeners first. As a result, `editor_controller`, the four block builders, site links, the markdown check, draft recovery, save and preview all work against either editor without knowing which one is running.

Code that needs more than a textarea can do checks `textarea.roeEditor`. That property is present only when the live editor is running.
- `goTo` / `goToLine` / `revealPos` place a line using CodeMirror's measured heights, clear of the sticky toolbar and the action drawer. Jump to heading, jump to line in the markdown check, and the footnote jumps all use them.
- `footnoteAt` / `footnoteContinuation` decide whether the caret is in a footnote using the syntax tree.

| File | Does |
|------|------|
| `editor.js` | The editor, the textarea stand-in, keyboard shortcuts, scroll placement |
| `syntax.js` | Markdown grammar: CommonMark + GFM tables/strikethrough + `==highlight==`, `\|\|aside\|\|`, footnotes |
| `live_preview.js` | Hides markers except where the caret is: per element for inline marks, per line for headings, quotes and lists |
| `roe_blocks.js` | Roe-anji block cards, automatic gallery detection, server warning checks |
| `footnotes.js` | Footnote detection, Enter indent, paste indent |

**Block cards** come from fenced blocks of the kinds `to_html` skips: `collection`, `card`, `gallery`, `form`, `button`, `search`. They also come from runs of consecutive image lines, found by `autoGalleryRuns()`, which mirrors `process_auto_galleries`. Keep the two in step. Each card is one row per source line at the editor's line height, so opening and closing a block never moves the page.

Broken blocks are found by `POST /admin/markdown/blocks`. It renders each block through `to_html(preview: true)` and returns any `[data-roe-warning]` boxes, which are marked by `dev_warning`. The editor shows that box in place of the card.

Styles are in the `MARKDOWN EDITOR` section of `app/assets/stylesheets/application.css`. Anything that sets the editor's own padding has to go through `EditorView.theme` in `editor.js`, because CodeMirror's injected styles outrank the stylesheet. The `roe-md-editor` class is set through `editorAttributes` for the same reason: CodeMirror rewrites the class attribute.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + S` | Save |
| `Cmd/Ctrl + P` | Preview |
| `Cmd/Ctrl + Shift + P` | Toggle preview |
| `Cmd/Ctrl + B` | Insert bold |
| `Cmd/Ctrl + I` | Insert italic |
| `Cmd/Ctrl + K` | Insert link |
| `Cmd/Ctrl + Shift + C` | Insert code block |

### Card Insertion

Insert cards via the editor toolbar or keyboard shortcut:

| Action | Toolbar Button | Creates |
|--------|-----------------|---------|
| Gallery | `GALLERY` | ` ```gallery ``` ` |
| Pullquote | `CARD ▼` | ` ```card type: pullquote ``` ` |
| Aside | `CARD ▼` | ` ```card type: aside ``` ` |
| Post Link | `CARD ▼` | ` ```card type: post-link ``` ` |
| Product Link | `CARD ▼` (Store) | ` ```card type: product-link ``` ` |
| Collection | `COLLECTION` | ` ```collection ``` ` |
| Button | `ACTION ▼` | ` ```button for: … ``` ` |
| Form | `ACTION ▼` | ` ```form for: … ``` ` |
| Paywall | `ACTION ▼` | ` ```form for: paid_content ``` ` |

### Post Search (for Post Links)

Press `@` or use the Post Link card to search posts:

```
@ruby     → Posts tagged or titled with "ruby"
@2024     → Posts from 2024
```

### Unsaved Changes

- Visual indicator appears when content is modified
- Warning shown on navigate away with unsaved changes
- Prompts before closing browser tab

### Scroll Position

- Scroll position is preserved across saves and page navigation
- Editor state (cursor, scroll) restored on page load

### Auto-Refresh

Preview pane auto-refreshes via BroadcastChannel when content is saved from another tab.

---

## Metadata Editor

The structured metadata editor (`app/views/shared/_metadata_editor.html.erb`) replaces raw YAML editing.

### Features

- Form-based fields for known metadata keys
- Raw YAML view toggle
- Dynamic field adding/removing
- Real-time validation
- Dual-view synchronization (form ↔ YAML)

### Field Types

| Type | Input | For |
|------|-------|-----|
| `text` | Text input | title, author, slug |
| `date` | Date picker | date |
| `select` | Dropdown | status, post_type |
| `array` | Tag input | tags |
| `textarea` | Text area | description, excerpt |
| `image` | File picker | featured_image |

### Status Selector

```
[Draft] [Published] [Unlisted]
```

---

## Media Browser

Access at `/admin/medium/browse`.

### Features

- Grid view of uploaded images/media
- Upload via drag-and-drop or file picker
- Click to insert Markdown into editor
- Automatic path insertion

### Uploaded Media Location

Files are stored in `site/media/`:
- Images: `site/media/images/`
- Other files: `site/media/files/`

### Inserting Media

1. Open media browser
2. Click image/file
3. Markdown inserted at cursor: `![Alt](path/to/file.jpg)`

### Supported Formats

- Images: jpg, jpeg, png, gif, webp, svg
- Fonts: ttf, woff, woff2, otf
- Documents: pdf

---

## Configuration Editor

Access via `/admin/configs`.

### site.yml

Structured form editor for main site configuration:
- Basic info (title, description, author)
- Feed settings
- Font configuration
- Navigation structure

### cards.yml & collections.yml

Raw YAML editor with syntax highlighting and validation.

---

## Layout Editor

Edit site layout templates at `/admin/layouts`:
- **Navigation**: `site/layout/navigation.md`
- **Footer**: `site/layout/footer.md`

Layout files are plain Markdown without frontmatter.

---

## Post Template

Default template for new posts at `/admin/settings/post_template`.

Content of this file is used as the starting point when creating new posts.

---

## Related

- [Content System](./02-content-system.md) - File format
- [Collections](./03-collections.md) - Collection insertion
- [Markdown Extensions](./04-markdown-extensions.md) - Card types
- [Routes](./08-routes.md) - All routes reference
- [Members & Authentication](./11-members-authentication.md) - Member management UI
- [Podcasts](./13-podcasts.md) - Podcast configuration UI
- [Substack Importer](./15-substack-importer.md) - Import dashboard
- [Media System](./17-media-system.md) - Media browser and picker
- [Tooltips](./10-tooltips.md) - Help tooltips in admin forms

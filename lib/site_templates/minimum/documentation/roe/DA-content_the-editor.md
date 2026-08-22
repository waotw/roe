---
title: "The Editor"
post_type: documentation
status: published
url_name: the-editor
tags: content
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# The Editor

## Metadata Section

The `metadata` for the post/page/product can be edited through a form or you can access the YAML directly through the `RAW` button. Click the `▶︎` to see the metadata, click the `▼` to hide it. If you're very curious, you can see a detailed walkthrough of all fields: [Metadata Fields](/documentation/roe/metadata-fields)

As you change things, certain new metadata fields may show up: changing `post_type` from `article` to `podcast` will show fields related to podcasts.

You can use the `+ Add Field` button to see a list of suggested fields as well as an option to add a `Custom field`.

## Content Section

### Keyboard Shortcuts

| Command       | Action           |
| ------------- | ---------------- |
| cmd/ctrl–s    | Save             |
| cmd/ctrl–p    | Open Preview     |
| cmd/ctrl–b    | Bold             |
| cmd/ctrl–i    | Italic           |
| cmd/ctrl–~    | Strikethrough    |
| cmd/ctrl–k    | Link             |
| cmd/ctrl-z    | Undo             |

### Saving & Preview

Roe does no auto-save; you're in control. Use `cmd/ctrl–s` (or the `SAVE` button). A small **status dot** next to Save shows where you stand: **amber** when you have unsaved changes, **green** once everything's saved.

Hit `cmd/ctrl–p` (or the `PREVIEW` button) to open a live preview in a new tab. It shows your work *including unsaved changes*, so you can see how things look before you save. Put The Editor and the Preview tab side-by-side, while you write and it **refreshes as you type**, so you can see how things will look as you go.

### Table of Contents and Markdown Check

Below the buttons are two tabs sharing one panel: `Table of Contents` and `Markdown Check`. Open either with its `▶︎`. Only one shows at a time, so opening one closes the other.

**Table of Contents** lists the headings in what you're writing. Use it to:

- jump to a particular heading, which is a help in a long piece. It closes as soon as you start typing.
- copy a link that goes straight to that heading

**Markdown Check** helps you format your markdown correctly. A dot tells you where you stand: **green** when your markdown is sound, **amber** when something wants a look. Roe checks when you open a post and again whenever you pause typing so it checks things in real-time.

The `Markdown Check` tab only appears when there's something to say. Open it and you'll find two lists:

- **Fixable** — things with one obvious correction. `FIX ALL` applies them, and `UNDO FIX` puts them back. A missing blank line above a list is the common one.
- **Needs your attention** — things only you can decide. An unclosed collection block, say: Roe can see that it never closes, but can't guess exactly where you intended to close it.

Click any line number to jump to it.

Fixes are applied in the editor, not to the file — nothing is saved until you save. `cmd/ctrl–z` undoes a fix like any other edit, and closing without saving discards it.

### Formatting Buttons

The format buttons for `B`, `I` and <code><s>S</s></code> allow you to select text and then apply the needed Markdown to those elements.

The `1. LIST` and `• LIST` buttons will start an ordered or unordered list:

- hit enter once to create the next item
- hit enter twice to exit out of the list

The `🔗` button will wrap the selected text in Markdown link syntax and move the cursor between the parenthesis so you're ready to paste the URL.

The <code>F<sup>1</sup></code> button creates a footnote:

1. Put the cursor where you want the foot note added.
2. Click the button and it will bring you to the bottom of the editor to add your footnote text.
3. Click `✓ DONE WITH FOOTNOTE` and it will bring you write back to where you inserted the footnote.

### [Roe-anji](/documentation/roe/roeanji) Buttons

You can edit the defaults for all Roe-anji features here: [Settings → Defaults](/admin/configs)

`GALLERY` opens a menu to build a gallery block — optionally toggle a carousel, pick an aspect ratio, and add a caption — then drops it at your cursor with a placeholder for your images. This isn't required for simple galleries, only for more complex layouts. More details here: [Galleries](/documentation/roe/galleries)

`CARD ▼` will open a menu with card options:

- Pull Quote - stylized text pulled out of the flow of the body text
- Post Link - stylized link to another post in your site.
- Aside - text/image that runs alongside the text at large sizes and sits within the text at smaller sizes.
- Product Link - stylized link to a product (only shown when the [Store](/documentation/roe/store) is enabled).

Clicking an option opens a short form for that card and drops the finished syntax at your cursor. Post Link and Product Link let you search for the item and pull its details in automatically.

You can learn about each of these in detail here: [Cards](/documentation/roe/cards)

`COLLECTION` opens as builder as well. Collections have many options and are very powerful and you can learn all about them here: [Collections](/documentation/roe/collections)

`ACTION ▼` opens a menu to insert an interactive element. It appears when the [Store](/documentation/roe/store) or [Members](/documentation/roe/members) feature is on, and each option opens a short form where you pick the type and fill in the fields (all optional — blanks use sensible defaults):

- **Button** — a store product button, a **Share** button, or a **Subscribe** button (links to your sign-up page).
- **Form** — Sign up, Sign in, Checkout, Donate, or Unsubscribe. Shown when Members is enabled.
- **Paywall** — a shortcut that opens the form pre-set to the paid-content upgrade block. Shown when payments are enabled.

Only the options your enabled features support are listed (e.g. Product needs the Store; Subscribe and the forms need Members; Paywall needs payments). Full details: [Forms & Buttons](/documentation/roe/forms-and-buttons)

`MEDIA ▼` will open a menu to insert media:

- **Images**
- **Audio**
- **Video**
- Select media type. From there you can:
    - Search
    - Click one or more items to select them
    - Upload new files directly
    - Click `Insert Selected` to insert the Markdown at your cursor position

Selecting 3 files to insert will add them one per line, which in the case of images creates a simple gallery:

```markdown
![image-one](/media/images/image-one.jpg)
![image-two](/media/images/image-two.jpg)
![image-three](/media/images/image-three.jpg)
```

Insertions are undoable with `cmd/ctrl–z`.

Manage all your files — rename, find, and clean up — in the [Media Browser](/documentation/roe/media).

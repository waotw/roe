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

The `metadata` for the post/page/product can be edited through a form or you can access the YAML directly through the `RAW` button. Click the `▶︎` to see the metadata, click the `▼` to hide it. If you're very curious, you can see a detailed walkthrough of all fields: [Metadata Fields](/documentation/metadata-fields)

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

### Table of Contents

You can access the TOC same as the metadata with the `▶︎` button. This allows you to:

- jump to a particular heading and is great for navigating long documents. It will close as soon as you start typing.
- copy a url that links directly to that heading

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

### [Roe-anji](/documentation/roeanji) Buttons

You can edit the defaults for all Roe-anji features here: [Settings → Defaults](/admin/configs)

`GALLERY` opens a menu to build a gallery block — optionally toggle a carousel, pick an aspect ratio, and add a caption — then drops it at your cursor with a placeholder for your images. This isn't required for simple galleries, only for more complex layouts. More details here: [Galleries](/documentation/galleries)

`CARD ▼` will open a menu with card options:

- Pull Quote - stylized text pulled out of the flow of the body text
- Post Link - stylized link to another post in your site.
- Aside - text/image that runs alongside the text at large sizes and sits within the text at smaller sizes.
- Product Link - stylized link to a product (only shown when the [Store](/documentation/store) is enabled).

Clicking an option opens a short form for that card and drops the finished syntax at your cursor. Post Link and Product Link let you search for the item and pull its details in automatically.

You can learn about each of these in detail here: [Cards](/documentation/cards)

`COLLECTION` opens as builder as well. Collections have many options and are very powerful and you can learn all about them here: [Collections](/documentation/collections)

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

Manage all your files — rename, find, and clean up — in the [Media Browser](/documentation/media).

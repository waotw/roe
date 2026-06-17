---
title: "Content: The Editor"
post_type: documentation
status: published
---
# The Editor

## Keyboard Shortcuts

| Command    | Action       |
| ---------- | ------------ |
| cmd/ctrl–s | Save         |
| cmd/ctrl–p | Open Preview |

## Metadata

The `metadata` for the post/page can be edited through a form or you can access the YAML directly through the `RAW` button. Click the `▶︎` to see the metadata, click the `▼` to hide it.

Find more details about how metadata works here: [Metadata](/documentation/metadata)

## Editor

### Table of Contents

You can access the TOC same as the metadata with the `▶︎` button. This allows you to:

- jump to a particular heading and is great for navigating long documents. It will go away as soon as you start typing.
- copy a url that links directly to that heading

### Buttons

The format buttons for `B`, `I` and <code><s>S</s></code> allow you to select text and then apply the needed markdown to those elements.

The `1. LIST` and `• LIST` buttons will start an ordered or unordered list:

- hit enter once to create the next item
- hit enter twice to exit out of the list

The `🔗` button will wrap the selected text in markdown link syntax and move the cursor between the parenthesis `(|)` so you're ready to paste the URL.

The <code>F<sup>1</sup></code> button creates a footnote:

1. Put the cursor where you want the field note added.
2. Click the button and it will bring you to the bottom of the editor to add your footnote text.
3. Click `✓ DONE WITH FOOTNOTE` and it will bring you write back to where you insterted the footnote.

### Feature Buttons

You can edit the templates for the `CARD` and `COLLECTION` buttons on the [settings page](/admin/configs)

`GALLERY` will add the image gallery syntax to the editor at the current cursor position. This isn't required for simple galleries, only for more complex layouts. More details here: [Galleries](/documentation/galleries)

`CARD ▼` will open a menu with card options:

- Pull Quote - stylized text pulled out of the flow of the body text
- Aside - text/image that runs alongside the text at large sizes and sits within the text at smaller sizes.
- Post Link - stylized link to another post in your site.

Clicking the option will drop the syntax at your cursor in the editor. Post-link allows you to search for any post in your system and then select it.

You can learn about each of these in detail here: [Cards](/documentation/cards)

`COLLECTION` will drop in the basic Collections syntax at your cursor in the editor. Collections are very powerful and you can learn all about them here: [Collections](/documentation/collections)

`MEDIA ▼` will open a menu to insert media:

- **Images**
- **Audio**
- **Video**

Clicking an option opens a media picker for that type. From there you can:

- Search
- Click one or more items to select them
- Upload new files directly
- Click `Insert Selected` to insert the markdown at your cursor position

Selecting 3 files to insert will add them one per line, which in the case of images creates a simple gallery:

```
![image-one](/media/images/image-one.jpg)
![image-two](/media/images/image-two.jpg)
![image-three](/media/images/image-three.jpg)
```

Insertions are undoable with `cmd/ctrl–z`.

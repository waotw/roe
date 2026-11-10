---
title: Collection Templates
status: published
url_name: collections_templates
tags: roe-anji
related:
  - collections
  - roeanji
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
order: title
```

# What are Collection templates?

A Collection is a list of your content, and a template decides how that list looks. Most of the time you'll reach for one of four: [`list`](#when-to-use-the-list-template) (the default for every Collection except Products, which default to `grid`), [`compact`](#when-to-use-the-compact-template), [`full`](#when-to-use-the-full-template), or [`links`](#when-to-use-the-links-template).

Three more templates handle special cases: [`menu`](#when-to-use-the-menu-template), [`grid`](#when-to-use-the-grid-template), and [`glossary`](#when-to-use-the-glossary-template).

This guide covers each template — what it shows and when to use it. Most fields can be turned on or off with an option like `show_author: true`, though which ones you can toggle depends on the template. A Collection only shows what its items actually have: if a Post has no image, it still appears in the Collection, just without one.

## When to use the `list` template

The `list` template looks like the feed on most blogs and newsletters. Each item shows:

- `title`
- `subtitle` — on by default; `show_subtitle: false` to hide it
- `date` — on by default; `show_date: false` to hide it
- `author` — off by default; `show_author: true` to show it

`author` is off by default because most sites have a single author, so repeating the name under every item just adds noise. `list` never shows an image — for an image feed, use `full`.

## When to use the `compact` template

The `compact` template gives you a tighter, cleaner list. Each item shows:

- `title`
- `date`
- `author` — off by default; `show_author: true` to show it

Reach for `compact` when you want a short, dated list of posts.

## When to use the `full` template

The `full` template adds an image and an excerpt to the feed. Each item shows:

- `image` — whenever the item has one
- `title`
- `subtitle` — on by default; `show_subtitle: false` to hide it
- `excerpt` — whenever the item has one
- `date` — on by default; `show_date: false` to hide it
- `author` — off by default; `show_author: true` to show it

## When to use the `links` template

The `links` template is a plain list of links — to pages on your site or anywhere else. Each item shows:

- `title`
- `subtitle`, when the item has one

A common use: tag a set of posts with `tags: links`, then point a `links` Collection at that tag to show only those. That way you can keep "link posts" out of your main feed and gather them here instead.

## What are the special templates?

### When to use the `menu` template

The `menu` template is a clean list of links — no subtitle, date, or author, just the links. Use it for the navigation at the top of your site, a list of links in a sidebar, or the links in your footer. It has its own options:

- `style` — lay the links out `horizontal` or `vertical`
- `collection` — give this Collection a name (any Collection can take a name, but it's most useful on a `menu`)
- `order` — a comma-separated list of `url_name`s; the links appear in exactly that order

`order` lets you set the exact sequence, which matters for a menu. Here is what that looks like:

```markdown
order: home, blog, shop, about, contact
```

When a `menu` lives in a sidebar, `style` sets its orientation on a full-size screen. On a narrow screen the sidebar can move under the header or below your content, and the links change orientation to fit. See [the sidebar options](/documentation/roe/admin_layouts#the-sidebar-on-narrow-screens) for `mobile` and `mobile_style`.

#### Why give the `collection` a name?

Once a `menu` has a name, you can send content to it. Say you're editing a new Page and want it in your site's navigation:

- add `collection: nav` to the `menu` Collection in your [header](/admin/layouts) layout
- add `collection: nav` to the new Page's metadata

The Page now shows up in the header on its own. To place it at a specific spot, add its `url_name` to the menu's `order`, as shown above.

### When to use the `grid` template

The `grid` template is the main way to show Products from your Store. If you don't see "Products" beside "Posts" in the Admin, open [Admin → Settings](/admin/configs/) and click the `ENABLE STORE` button, add your settings and click `SAVE`. Once your Collection uses `source: products`, the `grid` option appears.

A `grid` lays your products out as cards. Every card shows the same four things, and you can't turn them off:

- `title`
- `image`
- `price`
- `button` — an `Add to Cart` or `View` button

You can add one more field, off by default:

- `description` — set `show_description: true` to show each product's description

A `grid` Collection also has its own options:

- `category` — show only products in this category
- `groups` — set to `true` to show grouped products as a single card, such as one book sold as ePub, Paperback, and Hardback
- `aspect_ratio` — the shape of the product images in the grid

### When to use the `playlist` template

A `playlist` lays out music tracks or podcast episodes as a numbered list. A [player card](/documentation/roe/cards#player) on the same page plays it: clicking a row loads that track into the player, so a visitor can work through a release without the page jumping about.

The number is the track's `track_number`, or the episode's label (`E10`, `S1E10`). A row with no number needs one added to that post.

The list folds away under a `Tracks [9]` or `Episodes [9]` line. `fold: true` starts it folded and `fold: false` open. Without `fold`, it's folded on a music or podcast post, which is about its own track or episode, and open anywhere else.

A release is a collection filtered to it and ordered by track number, under a player card:

````markdown
```card
type: player
```

```collection
source: posts
post_type: music
release: the-quiet-hours
order: track_number
template: playlist
```
````

`order: track_number` is what puts them in running order. Without it you'll get them by date, which is rarely what a release wants.

Without a player card, each row plays on its own with the browser's audio controls. With one, the player plays the first playlist after it on the page. Straight after the card, the list joins it into one box.

You may not need to write this at all. The `[player]` and `[playlist]` boxes in a [content layout](/documentation/roe/layouts#content-layouts) draw the same player and list for a music track, a podcast episode, or a [page connected to a release or podcast](/documentation/roe/pages#release-and-podcast-pages).

### When to use the `glossary` template

The `glossary` template renders a column of short definitions. Roe's own [glossary](https://go-roe.com/documentation/roe/glossary) is built this way. Most sites won't need it. Each entry shows:

- `title` — the term being defined
- `subtitle` — a short definition
- `excerpt` — a longer definition or extra context
- `link` — a URL the term links to (a Wikipedia article or other reference, for example)

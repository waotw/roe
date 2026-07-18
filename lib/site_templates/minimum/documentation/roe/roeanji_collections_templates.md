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

#### Why give the `collection` a name?

Once a `menu` has a name, you can send content to it. Say you're editing a new Page and want it in your site's navigation:

- add `collection: nav` to the `menu` Collection in your [navigation](/admin/layouts) layout
- add `collection: nav` to the new Page's metadata

The Page now shows up in the navigation on its own. To place it at a specific spot, add its `url_name` to the menu's `order`, as shown above.

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

### When to use the `glossary` template

The `glossary` template renders a column of short definitions. Roe's own [glossary](https://go-roe.com/documentation/roe/glossary) is built this way. Most sites won't need it. Each entry shows:

- `title` — the term being defined
- `subtitle` — a short definition
- `excerpt` — a longer definition or extra context
- `link` — a URL the term links to (a Wikipedia article or other reference, for example)

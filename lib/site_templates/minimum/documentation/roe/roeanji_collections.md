---
title: Collections
status: published
url_name: collections
tags: roe-anji
related:
  - roeanji
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Collections

A Collection is a list of your content — posts, pages, products, or documentation — that you drop anywhere with a short block. One Collection can power an entire blog; another can add three "Featured Posts" to your home page. They can even build your site's menus — the header, footer, or sidebar (see [Build a menu, footer, or sidebar](#build-a-menu-footer-or-sidebar)).

You don't have to write the block by hand. In [The Editor](/documentation/roe/the-editor), click the `COLLECTION` button: it opens a form with every option below, shows each field only when it applies (the product options appear once you set the source to `products`), and writes just the fields you fill in. It then drops the finished `collection` block at your cursor. Set your Collection defaults in [Admin/Settings](/admin/configs/collections/edit).

## Options

You won't need most of these. Start with a bare block and add options only as you need them — a Collection with no options at all still works.

### Source & Filtering

| Option | Required | Description |
|--------|----------|-------------|
| `source` | No | `posts` (default), `pages`, `documentation`, or `products` |
| `tags` | No | Comma-separated, use `-tag` to exclude |
| [`collection`](#build-a-menu-footer-or-sidebar) | No | Comma-separated names; gathers content tagged with a matching `collection:` field |
| `category` | No | Filter products by category |
| `podcast` | No | Filter posts by podcast key/name |
| `post_type` | No | Filter posts by type: `article`, `audio`, `video`, `podcast` or `all`|
| [`related`](#show-related-content) | No | `true` shows items linked via frontmatter `related:`|

### Ordering

| Option | Required | Description |
|--------|----------|-------------|
| `order` | No | `date` (newest first, default), `date-asc` (oldest first), `title` (alphabetical), `filename` (numeric prefix aware, a file that starts with `0-` will be at the top), or a comma-separated list of `url_name`s for a hand-picked order (see [Pick the order by hand](#pick-the-order-by-hand)) |

#### Pick the order by hand

Instead of a sort mode, give `order:` a comma-separated list of `url_name`s. The items appear in exactly that order:

````
```collection
source: pages
order: blog, about, store
```
````

Items you don't name fall to the end, alphabetically — so nothing disappears if you forget one. The whole order lives in the block, so each collection can arrange things its own way, and you never edit the individual pages.

The [`menu`](#build-a-menu-footer-or-sidebar) template is the one exception: there the list *is* the menu, so anything you don't name is left out rather than appended.

### Display

| Option | Required | Description |
|--------|----------|-------------|
| `template` | No | `list` (default), `grid` (products default), `compact`, `links`, `menu`, `full`, or `glossary` |
| `style` | No | For the `menu` template only: `vertical` (default) or `horizontal` |
| `limit` | No | Number or `all` — defaults to [collection config](/admin/configs/collections/edit) or 10 |
| `offset` | No | Skip first `N` items, e.g., `offset: 10` |
| `heading` | No | Section heading above collection |
| `show_author` | No | `true` = show author name |
| `show_date` | No | `true` = show date |
| `show_subtitle` | No | `true` = show subtitle |
| `show_excerpt` | No | `true` = show excerpt |
| `show_more` | No | `true` = Add "View all" link to full [collection pagination](/documentation/roe/collections_pagination) (posts only) |
| `show_more_text` | No | Custom text for `show_more link` (default "View all") |

### Products

| Option | Required | Description |
|--------|----------|-------------|
| `category` | No | Filter products by category |
| `groups` | No | `enabled` to group variants together (e.g., Paperback/Hardback/Ebook of same book) |
| `aspect_ratio` | No | Product image ratio: `original` (default), `square`, `portrait`, `tv`, `wide`, or `cinema` (`auto`, `landscape`, and `film` are accepted aliases) |
| `show_description` | No | Show truncated product description (~100 chars) below the title |

#### [Grouped products](/documentation/roe/products#product-variants-groups)

When variants share a `group:` (e.g. Paperback/Hardback/Ebook of one book) and you set `groups: enabled`:

- The grid uses the **primary** variant's image and links to its page.
- Variant names appear in parentheses below the title (e.g. `(Paperback, Hardback)`).
- Price display is set in [Admin → Settings → Store](/admin/configs/store/edit):
  - `price_display: range` — `$10.00 - $25.00` (default)
  - `price_display: lowest` — `$10.00`
  - `price_display: highest` — `$25.00`
  - `price_separator` — separator for range prices (default `-`)
- `button_text` — an `Add to Cart` button doesn't really make sense for a product with several options to purchase — this button will link to the primary product page for that group; the default is "View".
- Individual (non-grouped) products show an "Add to Cart" button directly in the grid.

To add a default Collection to your Post/Page, this is all you need:

````
```collection
```
````

Left empty like that ↑, the block uses your defaults ↓ :

```markdown
default_source: posts
default_post_type: all
default_order: date
default_limit: 10
default_template: list
```

↑ Edit these defaults in [Admin → Settings → Collections](/admin/configs/collections/edit). Override any of these defaults by adding that option to the block ↓

## Make a feed of every article

Try the `compact` template:

````markdown
```collection
limit: all
template: compact
post_type: article
```
````

↑ Add this to a Page you're editing and click `PREVIEW`.

## Add a `heading`
↓ Give the Collection a `heading`:

````markdown
```collection
heading: everything I've ever written
limit: all
template: compact
post_type: article
```
````

## Build a menu, footer, or sidebar

A Collection isn't only for the body of a page — it works in your **layout files** too: `header`, `footer`, and `sidebar` (edit these in [Admin → Layouts](/admin/layouts)). Instead of hand-writing links, you build the menu from your own content.

The simplest way is to list the pages you want, in the order you want them. In your `header` layout file:

````
```collection
template: menu
order: blog, about, store
```
````

That's the whole menu — those pages, in that exact order. No tagging, no per-page edits: the `order:` list *is* the menu. The layout editor's `SHOW LINKS` panel lists every `url_name` you can drop in.

A few things worth knowing:

- `template: menu` outputs a bare list of links — no headings, no dates, no excerpts.
- The source defaults to `pages` (the usual case). Set `source: posts` or `products` to build the menu from those instead.
- `style: horizontal` lays the links out in a row; the default, `vertical`, stacks them.
- A `url_name` the list can't find is skipped (and logged in development, so a typo is easy to catch).
- A menu shows every link you give it — it isn't capped at ten like the other templates.
- In the `header` file, the current page's link gets an `active` class automatically, so you can highlight it in CSS.

### Or let the menu fill itself

Prefer a menu that keeps itself current — every page meant for the footer shows up there, with no list to maintain? Tag the pages instead. Give each one a `collection:` field naming the menu it belongs to:

```yaml
collection: footer
```

The name is yours to choose — `footer`, `resources`, `main-menu`, whatever fits. Then point a `menu` Collection at that name and leave `order:` off:

````
```collection
template: menu
collection: footer
```
````

Every page tagged `collection: footer` now appears, alphabetically — tag a page and it joins the menu, no layout edit needed. A page can belong to more than one: `collection: footer, main-menu` puts it in both. Think of `collection:` as placement the way [tags](#source--filtering) are subject — it gathers content by the menu it belongs to instead of by topic.

Use whichever fits — or **both**. Give a `menu` Collection an `order:` list *and* a `collection:` name, and the menu is the two combined: listed pages come first, in your order; anything tagged but not listed follows, alphabetically. Like `related`, it works from either side — name a page in the list here, or tag the page itself — so nothing you meant to include gets dropped.

## Show `related` content

I'm using a `related` collection at the top of this document in [Related documentation](#related-documentation). Here's an example of how `related` works:

On a product page for a blue t-shirt, you add this ↓

````markdown
```collection
heading: You might also like…
source: products
template: links
related: true
```
````

↑ This narrows the Collection to just the `related` items. But how do you make something `related`?

Add a `related` entry to any Post, Product, or Page, and the two pieces of content are now connected. Here I add the `url_name` for **Blue T-shirt** ↓ to my **Yellow T-shirt** product's metadata:

![Related field in metadata for Yellow T-shirt Product](/media/images/related_product_metadata.png)

The link is `bi-directional` — you set it on one side, and both sides see it. I added `blue-tshirt` to **Yellow T-shirt**, and it shows up in the `related: true` Collection on **Blue T-shirt's** page just the same.

## Paginate with a "View all" link

Often, a home page or blog page will show 5-10 posts, then link to the archive for the rest. A Collection makes this easy.

````markdown
```collection
heading: Music
limit: 1
show_more: true
```
````

↑ This shows the most recent post tagged "music" and adds a "View all" link below the Collection. To change the label, set `show_more_text:` ↓

````markdown
```collection
heading: Music
limit: 1
show_more: true
show_more_text: All the music posts →
```
````

↑ That code renders like this ↓

---

```collection
heading: Music
limit: 1
show_more: true
show_more_text: All the music posts →
```

---

## Post Collection examples

### Last 5 featured posts

````markdown
```collection
heading: Featured
limit: 5
tags: featured
order: date
```
````

### Last 5 music-criticism posts, alphabetical

````markdown
```collection
heading: Music 
limit: 5
tags: music-criticism
order: title
```
````

## Product Collection examples

### All products in a grid

````markdown
```collection
source: products
template: grid
```
````

### Books only Collection, portrait format

````markdown
```collection
source: products
category: book
aspect_ratio: portrait
show_description: true
heading: Books
```
````

### Featured Products with descriptions

````markdown
```collection
source: products
tags: featured
template: grid
show_description: true
limit: 6
```
````

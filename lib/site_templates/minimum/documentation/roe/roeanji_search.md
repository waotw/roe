---
title: Search
status: published
url_name: roe-search
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

# Search

Roe has built-in site search[^1]. There are two ways search shows up on your site:

1. the always-present **[global search](#global-search)** in the header
2. an optional **[collection search](#collection-search)** icon you can add to any collection.

## Options

You *do not* have to configure any of these. Search works out of the box. These options just give you control over what's searchable and the context (scope) for search itself.

### Site-wide settings

Set these in [Admin → Settings → Search](/admin/configs/site/edit) (or directly in `site.yml`).

| Option | Description |
|--------|-------------|
| Include all pages in search | `unchecked = false` (default) only pages linked in your header/footer.<br>`checked = true` every published page. |
| Roe's documentation |`local` (default) excludes Roe's documentation from from your live site and search.<br>`published` include it in your live site.<br>`searchable` include it in your site and search |
| Show results before typing | `unchecked = false` (default) no results when search is opened<br>`checked = true` see results first, then filter as you type. |

### What is in search results

Search follows the same rules as the `status` and `audience` for pages, posts, products:

| Content | Shows up in search? |
|---------|---------------------|
| `status: published` | Yes (posts, products, documentation) |
| Pages | Only those in nav/footer (unless [`search_all_pages`](#site-wide-settings)) is on |
| `status: draft`<br>`status: unlisted`| No |
| `audience: paid` | No, unless [`Show paid content`](/admin/configs/members/edit#paid-content) is set to `true`, then previews show up in search |

> Tip: mark any single page or doc `unlisted` to keep it out of search, regardless of the settings above.

## Global search

The header search icon is always available. When clicked, it's **smart about [scope](#scope-options)**: it starts filtered to whatever you're currently looking at, shown as a small removable label. If there are no labels, that is full site search.

### Automatic scope

| You're on… | Search starts scoped to… |
|------------|--------------------------|
| A documentation page | `documentation` |
| A product page | `products` |
| A post | that post's type (`article`, `podcast`, …) |
| A collection page (`/collections/…`) | that collection's `source` / `post_type` / `tags` |
| A page with a `search_scope:` in its frontmatter | that scope |
| Anything else | Everything (site-wide) |

Clear the label and you're back to searching the whole site.

### Search result labels

Each result carries a small type label — `page`, `doc`, `prod.`, or a post type like `podcast`. On a site-wide search you can **click a result's label** to add that filter to your search and narrow the results. Click the `×` on an active label to remove it.

### Scope options

A scope is any combination of:

| Kind | Option |
|------|--------|
| Sources | `posts`, `pages`, `documentation`, `products` |
| Post types | `article`, `audio`, `video`, `podcast` (and any custom types) |
| Tags | include `tags: music`, or exclude`tags: -music` |

### Page-level scope

To scope the global search for a particular page, add `search_scope` to that page's frontmatter. You can add multiple options separated by commas; you can combine `source` & `post_type`.

```markdown
---
title: Shop
search_scope: products
---
```

↑ On this page, the global search starts filtered to just a `products` label, which can be easily removed for global search.

## Collection search

Any Collection can show its own search icon that opens the global search **pre-scoped to that collection's filters**. Just add `search: true` to your Collection options.

| Option | Required | Description |
|--------|----------|-------------|
| `search` | No | `true` adds a search icon beside the collection, scoped to its `source`, `post_type`, and `tags` |

Because it reuses the collection's own filters, the search always matches what the collection shows, i.e. `podcast episodes, with music tags`.

### Examples

Search your journal (posts tagged `journal`) right from where it's listed:

````markdown
```collection
heading: Journal
source: posts
tags: journal
search: true
```
````

Search your documentation:

````markdown
```collection
source: documentation
template: links
search: true
```
````

Search a product catalog:

````markdown
```collection
heading: Store
source: products
template: grid
search: true
```
````

## CSS

Elements related to search are semantically classed:

- `.site-search`
- `.site-search-overlay`
- `.site-search-input`
- `.site-search-results`
- `.site-search-context-label`
- `.site-search-trigger`
- find `site-search` in your theme's CSS to edit how this looks/feels

---

## Advanced: the `search` block *(experimental)*

There's an experimental `search` block for embedding a scoped search trigger directly in your content. Its exact behavior is still being refined, so it isn't recommended for general use yet — prefer collection search (`search: true`) for now.

**Example:**

````markdown
```search
scope: documentation
```
````

[^1]: Search is supported on static sites as well; it works exactly the same whether your site is served by Roe or deployed as static HTML.

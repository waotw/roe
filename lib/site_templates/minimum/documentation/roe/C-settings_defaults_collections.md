---
title: Settings → Collections
status: published
url_name: settings-collections
tags: settings
related:
  - collections
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Collections: Default Settings

These settings decide what a collection does by default. If the collection itself specifies something, the collection will win. Set the defaults at [Settings → collections.yml](/admin/configs/collections/edit) and all collections will work that way unless you change a specific collection.

## Defaults

- `default_source` — `posts`, `pages`, `documentation` or `products`.
- `default_post_type` — which posts to include: `all`, `article`, `podcast`, `music`, `audio` or `video`. Only applies when the source is `posts`.
- `default_order` — `date` (newest first), `date-asc` (oldest first), `title` or `filename`. Using `filename` lets you set an exact order by naming files `01-first-post`, `02-second-post` and so on.
- `default_limit` — how many items to show. A number, or `all`.
- `default_template` — the template determines how a collection is displayed: `list`, `compact`, `links`, `full`, `menu`,  `glossary` or `playlist`. When `source: products` it will default to `grid`.

## Pagination

These two apply to collections with `show_more: true`.

- `items_per_page` — how many items each page holds.
- `pagination_template` — the collection template used by the pagination pages.

## How the collection builder uses default settings

`COLLECTION` in [the editor](/documentation/roe/the-editor) opens the collection builder, and each field will default to the default settings you've set for all collections. Change what you want and click Insert.

The builder inserts the collection with the default settings. You might notice that if you leave an option as the default, that option isn't written into the collection when you insert it. This is deliberate. This allows you to update all the collections from the global settings rather than having to update every collection one-by-one if you decide you want to change them.

If you want a collection to always have specific options (such as a particular template), add that option to the collection itself and that will override the global settings.

See all available [options for Collections](/documentation/roe/collections#options).

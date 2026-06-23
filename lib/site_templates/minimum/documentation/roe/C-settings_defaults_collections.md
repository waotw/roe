---
title: Defaults → Collections
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

# Collection: Default Settings & Template

This allows you to customize the defaults used in Collections, as well as the Buttons which generate the code in the Editor.

These defaults can always be overridden when using a Collection. Simply add the option you need.

## Defaults
- `default_source` - set your default `source` for Collections: `posts`, `pages`, `documentation`
- `default_post_type` - set your default `post_type` for Collections: `article`, `podcast`, `video`, `all`
- `default_order` - set your default `order` for Collections: `date`, `date-asc`, `title`, `filename` - using `filename` allows you to create a specific order, e.g. (01-first-post, 02-second-post) by editing the names of the files.
- `default_limit` - set your default `limit` - any number or `all`
- `default_template` - `list`, `links`, `compact`, `full`, 
- `items_per_page` - this sets the number of items when `show_more: true` is in the Collection. These apply to items in pagination.

## Button 

### The `COLLECTION` button in the editor

This button drops a `collection` template into your Markdown. This is where that template lives.

See all available [options for Collections](/documentation/collections#options)

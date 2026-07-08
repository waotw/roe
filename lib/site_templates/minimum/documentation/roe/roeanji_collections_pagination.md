---
title: Roe-anji → Collections & Pagination
status: published
url_name: collections_pagination
tags: roe-anji
related:
  - roeanji
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
order: title
```

# Collections & Pagination

Add pagination to a Collection by adding:

1. `limit: 5` (this number should be less than the total number of items in that Collection)
2. `show_more: true`

Like so ↓

````markdown
```collection
post_type: article
template: compact
tags: music
limit: 5
show_more: true
```
````

## Settings for Pagination

You can edit the settings for pagination at [Settings → Defaults → collections.yml](/admin/configs/collections/edit). There are 2 settings for pagination:

- `Items per page` - sets the number of items for pagination (default = `20`)
- `Pagination template` - sets the Collection template specifically for pagination (default = `list`)

## How pagination works?

Roe automatically creates the extra pages for you based on the Collection settings. 

### Page Heading

The pagination page heading is built from the Collection settings in this order:

1. `heading` a heading in the Collection settings will be the heading for pagination
2. `source` a source specified in the Collection settings: `posts`, `pages`, etc.
3. `tags` a tag in the Collection settings (first tag is used)
4. `post_type` a post_type other than `all` will be used: `article` → "Articles"
    - `post_type: podcast` podcast's title is used
    - if the Collection contains episodes from multiple podcasts, "Podcast" is used 
5. If there are no filter options in the Collection, the heading becomes "Archive"

### Static Site Generation

Roe does the same for a static site. All necessary pagination pages are generated automatically.

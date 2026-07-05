---
title: Roe-anji → Collections
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

Collections are lists of posts, pages, products, or documentation. They can power entire blogs or just add a few "Featured Posts" to your home page.

When writing anything that uses the Markdown editor, use the `COLLECTION` button to insert a Collection at the cursor location. The `COLLECTION` button template can be edited in [Admin/Settings](/admin/configs/collections/edit).

## Options

You *do not* have to use all of these. Collections are simple but flexible. These options give you flexibility but you can keep it simple.

### Source & Filtering

| Option | Required | Description |
|--------|----------|-------------|
| `source` | No | `posts` (default), `pages`, `documentation`, or `products` |
| `tags` | No | Comma-separated, use `-tag` to exclude |
| `category` | No | Filter products by category |
| `podcast` | No | Filter posts by podcast key |
| `post_type` | No | Filter posts by type: `article`, `audio`, `video`, `podcast` or `all`|
| [`related`](#show-related-content) | No | `true` shows items linked via frontmatter `related:`|

### Ordering

| Option | Required | Description |
|--------|----------|-------------|
| `order` | No | `date` (newest first, default), `date-asc` (oldest first), `title` (alphabetical), or `filename` (numeric prefix aware) |

### Display

| Option | Required | Description |
|--------|----------|-------------|
| `template` | No | `list` (default), `grid` (products default), `compact`, `links`, `full` or `glossary` |
| `limit` | No | Number or `all` — defaults to [collection config](/admin/configs/collections/edit) or 10 |
| `offset` | No | Skip first `N` items, e.g., `offset: 10` |
| `heading` | No | Section heading above collection |
| `show_author` | No | `true` = show author name |
| `show_date` | No | `true` = show date |
| `show_subtitle` | No | `true` = show subtitle |
| `show_excerpt` | No | `true` = show excerpt |
| `show_more` | No | Add "View all" link to full [collection pagination](/documentation/collections_pagination) (posts only) |
| `show_more_text` | No | Custom text for `show_more link` |

### Products

| Option | Required | Description |
|--------|----------|-------------|
| `category` | No | Filter products by category |
| `groups` | No | `enabled` to group variants together (e.g., Paperback/Hardback/Ebook of same book) |
| `aspect_ratio` | No | Image aspect ratio: `auto` (default), `portrait`, `square`, or `landscape` |
| `show_description` | No | Show truncated product description (~100 chars) below the title |

To add a default Collection to your Post/Page, this is all you need:

````
```collection
```
````

When left empty like the above ↑, the defaults will be used ↓ :

```markdown
default_source: posts
default_post_type: all
default_order: date
default_limit: 10
default_template: list
```

↑ The Collections defaults can be edited in [Admin/Settings](/admin/configs/collections/edit).
Any default can be overwritten by adding that parameter to the Collection ↓ 

## Create a feed (Collection) of All Articles

Try the `compact` template:

````
```collection
limit: all
template: compact
post_type: article
```
````
↑ Try adding this to a Page you're editing and click `PREVIEW`.

## Add a `heading`
↓ Try adding a `heading` to the Collection:

````markdown
```collection
heading: everything I've ever written
limit: all
template: compact
post_type: article
```
````

## Show `related` content

I'm using a `related` collection at the top of this document in [Related documentation](#related-documentation). Here's how `related` works:

On a product page for a blue t-shirt, you add this ↓

````markdown
```collection
heading: You might also like…
source: products
template: links
related: true
```
````

↑ this filters the Collection results to just the `related` results. But how do you make something `related`?

Add a `related` entry for any Post, Product, Page and those two pieces of content are now "related". I'll add the `url_name` for Blue T-shirt ↓ to my Yellow T-shirt Product metadata and now they are "related". 

![Related field in metadata for Yellow T-shirt Product](/media/images/related_product_metadata.png)

This is `bi-directional`, meaning you only have to add `related` to one item and then both are connected. Notice I added `blue-tshirt` to the **Yellow T-shirt**'s metadata, and it shows up in the `related: true` Collection I'm adding to **Blue T-shirt**'s product page — that's what `bi-directional` means. Once they're related by one connection, they're ***related***.

## Add Pagination/View All

Pagination is very common on a blog. You might want to show 5 posts on your home page and then link to the archive with the rest. Collections makes this easy.

````markdown
```collection
heading: Music
limit: 1
show_more: true
```
````

↑ That will show the most recent post tagged "music" and add a "View all" link to the bottom of the Collection. If you prefer something other than "View all", you can customize that with `show_more_text:` like so ↓ :

````markdown
```collection
heading: Music
limit: 1
show_more: true
show_more_text: All the music posts →
```
````

↑ That code will look like this ↓

---

```collection
heading: Music
limit: 1
show_more: true
show_more_text: All the music posts →
```

---

## Collection Examples:

### Last 5 Featured Posts

````markdown
```collection
heading: Featured
limit: 5
tags: featured
order: date
```
````

### Last 5 Music Criticism Posts sorted Alphabetically

````markdown
```collection
heading: Music 
limit: 5
tags: music-criticism
order: title
```
````

## Product Collection Examples:

### All Products in a Grid

````markdown
```collection
source: products
template: grid
```
````

### Books Only, Portrait Format

````markdown
```collection
source: products
category: book
aspect_ratio: portrait
show_description: true
heading: Books
```
````

### Featured Products with Descriptions

````markdown
```collection
source: products
tags: featured
template: grid
show_description: true
limit: 6
```
````

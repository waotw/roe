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
| `post_type` | No | Filter posts by type: `article`, `audio`, `video`, or `podcast` |
| `related` | No | `true` shows items linked via frontmatter `related:`|

### Ordering

| Option | Required | Description |
|--------|----------|-------------|
| `order` | No | `date` (newest first, default), `date-asc` (oldest first), `title` (alphabetical), or `filename` (numeric prefix aware) |

### Display

| Option | Required | Description |
|--------|----------|-------------|
| `template` | No | `list` (default), `grid` (products default), `compact`, `links`, or `full` |
| `limit` | No | Number or `all` — defaults to site config or 10 |
| `offset` | No | Skip first N items |
| `heading` | No | Section heading above collection |
| `show_author` | No | Show author name in list items |
| `show_excerpt` | No | Show excerpt in list items |
| `show_more` | No | Add "View all" link to full collection page (posts only) |
| `show_more_text` | No | Custom text for show_more link |

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

## Create a feed of All Articles

To create a feed of all articles with the `compact` template, you can do this:

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

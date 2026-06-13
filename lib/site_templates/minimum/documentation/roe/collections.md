---
roe_version: 0.0.20
title: Collections
status: published
---

# Collections

Collections are lists of posts. They can power entire blogs or just add a new "Featured Posts" to your home page.

When writing a Post/Page, user the `COLLECTION` button to insert a Collection at the cursor location. The `COLLECTION` button template can be edited in [Admin/Settings](/admin/configs/collections/edit).

To add a default Collection to your Post/Page, this is all you need:
````
```collection
```
````

When left empty like the above ↑, the defaults will be used ↓ :
````
```collection
default_source: posts
default_post_type: all
default_order: date
default_limit: 10
default_template: list
```
````

↑ The Collections defaults can be edited in [Admin/Settings](/admin/configs/collections/edit).
↓ Any default can be overwritten by adding that parameter to the Collection:

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

## Collection Options

### heading
(optional, add a heading to the collection)

- `heading: the heading I want above the collection`

### limit
(optional, default: 10, use `all` for everything) 

- `limit: 5`


### order
(Sort posts, default: `date`)

**Order options:**
  - `order: date` - (newest → oldest)
  - `order: date-asc` - (oldest → newest)
  - `order: title` - (alphabetical by post title)
  - `order: filename` - (create custom order by adding number to filenames)
    - example: `01-My Best Post.md`
    - example: `02-My Second Best Post.md`

### template

(optional, default: `list`) 

**Template options:**
  - `template: list` = Title (h3), subtitle (italic), date (italic)
  - `template: compact` = Title and date on single line, separated by bullet
  - `template: links` = Title and subtitle, no date
  
### tags
(Filter by tag, optional, default: none)

- `tags: arts, culture, music` = Give me only posts tagged with all three of these.
- `tags: arts, -politics` = Give me only posts tagged `arts` but filter out any posts tagged `politics`.
- `tags: -politics` = Give me everything but filter out any posts tagged `politics`.

### type (posts)
(Filter by type, optional, default: all types) 

- `post_type: music` = show me only posts with `post_type` of `music`.

### source
(Choose content type, optional, default: posts)

**Source options:**

  - `source: posts` - Blog posts (default)
  - `source: pages` - Pages
  - `source: documentation` - Documentation pages
  - `source: products` - Products from your store

### category (products)
(Filter products by category, optional, products only)

- `category: book` = show me only products in the "book" category
- Works only with `source: products`

### aspect_ratio (products)
(Control product image display, optional, products only)

**Aspect ratio options:**

  - `aspect_ratio: auto` - Natural image size, max height 400px (default)
  - `aspect_ratio: square` - 1:1 square format
  - `aspect_ratio: portrait` - 3:4 portrait format (good for books)
  - `aspect_ratio: landscape` - 4:3 landscape format
  - `aspect_ratio: wide` - 16:9 wide format

### show_description (products)
(Show product descriptions in grid, optional, products only)

- `show_description: true` - Display product descriptions (truncated to ~100 chars)
- Default: false

---

## Post Collection Examples:

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

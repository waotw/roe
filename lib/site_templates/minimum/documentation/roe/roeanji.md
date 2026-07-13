---
title: Roe-anji
status: published
url_name: roeanji
tags: roe-anji
related:
  - cards
  - collections
  - galleries
  - forms-and-buttons
  - roe-search
  - paid-content
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
order: title
```

# Roe-anji

Simple Markdown extensions that are easy to learn and use. They all use the same fenced-block syntax as a Markdown code block, and let you add rich content to your site beyond standard Markdown.

This page is a quick tour — one example apiece. Each extension has its own reference doc with the full list of options.

## Cards

Styled blocks — pullquotes, asides, and post/product links — embedded in your Markdown.

````markdown
```card
type: pullquote
text: There's only one way to find out…
```
````

Full reference → [Cards](/documentation/cards)

## Collections

Lists of your content — posts, pages, products, or docs — from a "Featured Posts" strip to a whole blog index.

````markdown
```collection
source: posts
limit: 10
template: list
heading: Latest Posts
```
````

Full reference → [Collections](/documentation/collections)

## Galleries

Group images into a responsive grid — automatically when images sit next to each other, or explicitly with a `gallery` block.

````markdown
```gallery
![alt1](/media/images/photo1.jpg)
![alt2](/media/images/photo2.jpg)
```
````

Full reference → [Galleries](/documentation/galleries)

## Forms & Buttons

Interactive elements: membership and payment forms, store buttons, and share/subscribe actions — all selected with `for:`.

````markdown
```form
for: signup
button-text: Sign Up
```
````

Full reference → [Forms & Buttons](/documentation/forms-and-buttons)

## Products

Show your store products as a grid with a `collection` — `source: products`. Grouping, image ratio, and price display are collection options.

````markdown
```collection
source: products
template: grid
```
````

Full reference → [Collections → Products](/documentation/collections#products) · [Store](/documentation/store)

## Search

Built-in site search — a global search in the header plus an optional per-collection search icon. It works out of the box; there's no block to add.

Full reference → [Search](/documentation/roe-search)

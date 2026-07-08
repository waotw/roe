---
title: Products
status: published
tags: content
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Products

Products in Roe are just [markdown](/documentation/glossary/#markdown) files, similar to Pages/Posts. They can be edited here: [Admin → Products](/admin/products). The files live in your `/site/products` folder and can be edited directly if you prefer. 

##### Before Products

You'll need to enable the Store feature, go to: [Admin → Settings](/admin/configs) and click `ENABLE STORE`. You will see see `store.yml` in the `Features` section.

## Products in Roe

Products are items you sell through your site using the [Store](/documentation/store) feature. Each product is a Markdown file with metadata for price, SKU, images, and more.

Products work with [Snipcart](https://snipcart.com) to handle the shopping cart, checkout, and payment processing.

## Creating Products

Create products in [Admin → Products](/admin/products) or add `.md` files to `/site/products`.

### Metadata

The Admin shows product metadata as a simple form; you can also edit it directly in the `.md` file.

![Product Metadata Form UI](/media/images/product-metadata.png)

```yaml
---
title: The First Book
status: published
url_name: my-first-book
sku: BOOK-001-MYFIRSTBOOK
price: 10.00
category: book
tags: fiction, poetry
image: /media/images/my-first-book.jpg
description: A lyrical meditation on memory and place
---
```

| Field | Required | Description |
|-------|----------|-------------|
| `title` | Yes | Product name |
| `sku` | Yes | Unique identifier — how Snipcart tracks the item at checkout (required to publish) |
| `price` | Yes | Price as a number (e.g., `10.00`) |
| `category` | Yes | Product category — used for filtering and SKU generation |
| `image` | Yes | Product image path |
| `status` | Yes | `draft` or `published` |
| `url_name` | No | Custom URL slug (auto-generated from the title if not set) |
| `tags` | No | Tags for filtering and organization |
| `description` | No | Short description shown in product grids |
| `group` | No | Groups variants together — see [Product Variants](#product-variants-groups) |
| `variant` | No | Label for this variant (e.g., "Paperback") |
| `primary` | No | `true` to show this variant first in a grouped collection |

## Product Variants (groups)

This allows you to sell different versions of the same thing, e.g. same t-shirt, different colors or same book title but different formats (ebook, paperback). You can edit the settings for product groups here: [Settings → Features → store.yml][/admin/configs/store/edit].

1. Create a product for each variant
2. Give them all the same `group` value
3. Set `primary: true` on the variant you want to show first
4. Label each with `variant`

```yaml
---
title: My Book
sku: BOOK-001-PAPER
price: 15.00
category: book
group: my-book
variant: Paperback
primary: true
---
```

In [Collections](/documentation/collections#products) with `groups: enabled`, Roe shows one entry per group and shows one price (lowest, highest or range). You can set this here: [Settings → Features → store.yml](/admin/configs/store/edit).

## SKUs

SKUs (Stock Keeping Units) are required for every product. They must be unique and should not be changed once your site is live and people have purchased items. <mark>Note:</mark> The SKU is how Snipcart identifies the item that is purchased. Don't change SKUs once a product is live and has been bought.

Roe includes a SKU generator that suggests standardized codes.

### SKU Generator

When creating a product, the SKU Generator is available in the metadata editor on any product page. This helps to create standardized SKUs:

![](/media/images/sku_metadata.png)

Suggested Pattern: `{CATEGORY}`-`{NUMBER}`-`{TITLE/NAME}`-`{VARIANT-DETAILS}`

- **Book Example:** `BOOK-001-MYFIRSTBOOK-PAPERBACK`
- **Shirt Example:** `TSHIRT-001-SHIRTNAME-RED-L`

The generator:

- Uses the `category`, `title`, `variant` if present to help build a SKU
- Auto-increments numbers within each category
- Makes sure that the SKU is unique

## Displaying Products

Details found in the [Store](/documentation/store#displaying-products-with-collections) article.

## Product Pages

Each product file is a 'page'. You can add content below the metadata (descriptions, sample chapters, reviews) using regular Markdown.

Use the `PRODUCT` button in [The Editor](/documentation/the-editor) to insert a template product page. This pulls from the metadata to give you a good starting point when building out product pages. (The `PRODUCT` button only appears while editing a product.)

To link to a product from a post or another page, use a [Product Link card](/documentation/cards#product-link) (`CARD ▼ → Product Link`) — it pulls in the product's title, price, and image automatically.

See [Store](/documentation/store) to learn about the Store feature in Roe.

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

A Roe site is mostly [Markdown](/documentation/glossary#markdown) and [YAML](/documentation/glossary#yaml) files. There are 4 sources of content in Roe: [Pages](/documentation/pages), [Posts](/documentation/posts), Products (if you've enabled the Store) and Documentation.

Your Product files are in the `/site/products` folder in your `Roe` folder (where you've installed Roe).

## Products in Roe

Products are items you sell through your site using the [Store](/documentation/store) feature. Each product is a Markdown file with metadata for price, SKU, images, and more.

Products work with [Snipcart](https://snipcart.com) to handle the shopping cart, checkout, and payment processing.

## Enabling the Store

Before creating products:

1. Go to [Admin → Settings](/admin/configs)
2. Click **Enable Store**
3. Configure your store settings (currency, categories)
4. Add your Snipcart API keys
5. See [Store](/documentation/store) for full setup instructions

## Creating Products

Create products in [Admin → Products](/admin/products) or add `.md` files to `/site/products`.

### Required Metadata

```yaml
---
title: The First Book
status: published
sku: BOOK-001-MYFIRSTBOOK
price: 10.00
category: book
image: /media/images/my-first-book.jpg
---
```

### Product Metadata Fields

| Field | Required | Description |
|-------|----------|-------------|
| `title` | Yes | Product name |
| `sku` | Yes | Unique identifier for checkout |
| `price` | Yes | Price as a number (e.g., `10.00`) |
| `category` | Yes | Product category for filtering |
| `image` | Yes | Product image path |
| `status` | Yes | `draft` or `published` |
| `url_name` | No | Custom URL slug |
| `tags` | No | Tags for organization |
| `description` | No | Short description shown in product grids |
| `group` | No | Groups variants together (see below) |
| `variant` | No | Label for this variant (e.g., "Paperback") |
| `primary` | No | Set `true` to show this variant first in collections |

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

In collections with `groups: enabled`, Roe shows one entry per group and shows one price (lowest, highest or range). You can set this here: [Settings → Features → store.yml][/admin/configs/store/edit].

## Displaying Products

Use [Collections](/documentation/collections) with `source: products` to display products:

```markdown
```collection
source: products
category: book
template: grid
heading: Books
```
```

Collection options for products:

| Option | Description |
|--------|-------------|
| `category` | Filter by product category |
| `groups` | `enabled` to group variants together |
| `show_description` | Show product description in grid |
| `aspect_ratio` | Image aspect ratio: `auto`, `portrait`, `square`, `landscape` |

## SKUs

SKUs (Stock Keeping Units) are required for every product. They must be unique and never change once set. Roe includes a SKU generator that suggests standardized codes:

```
BOOK-001-MYFIRSTBOOK
```

<mark>Note:</mark> Changing a SKU after customers have purchased breaks the connection between your product and Snipcart's records.

## Product Pages

Each product file is a 'page'. You can add content below the metadata (descriptions, sample chapters, reviews) using regular Markdown.

Use the `PRODUCT` button in [The Editor](/documentation/the-editor) to insert a template product page. This pulls from the metadata to give you a good starting point when building out product pages.

## Store Page

There is no Store page be default. Since Roe is modular, you can build a Store page easily. Create a page called: `Store`, and add a product [Collection](/documentation/collections#products) to it.

See [Store](/documentation/store) to learn about the Store feature in Roe.

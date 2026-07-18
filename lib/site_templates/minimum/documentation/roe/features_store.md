---
title: Store
status: published
tags: feature
url_name: store
related:
  - products
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Store

The Store feature lets you sell products directly from your site using [Snipcart](https://snipcart.com). Products are Markdown files similar to pages/posts with metadata for price, SKU, images, and more.

## Quick Start

There are 3 key pieces that must be in place for Snipcart & Roe to work together:

1. Roe needs the API Keys from Snipcart (covered here: [Snipcart](documentation/snipcart))
2. Your Store settings need to be set up (covered in this article)
3. You need at least one product (covered here: [Products](/documentation/roe/products))

This document has instructions for setting things up on the Roe side. Follow [Snipcart's documentation](https://docs.snipcart.com/v3/dashboard/store-configuration) for setting up things on their side. It's very good.

On the Roe side:

1. **Enable the Store** - Go to [Admin/Settings](/admin/configs/store/edit) and configure your store
2. **Connect Snipcart** - Add your Test Snipcart API keys in [Admin/Snipcart](/admin/snipcart_config/edit
3. **Create Products** - Use the [Products](/admin/products) page to add items
    - Make sure to add [SKUs](#sku-generator) to the Product metadata
4. **Display Products** - Use collections with `source: products` to show your catalog on any page.

## Store Page

There is no Store page be default. Since Roe is modular, you can build a Store page easily. Create a page called: `Store`, and add a product [Collection](/documentation/roe/collections#products) to it.

## Displaying Products with Collections

Products work with the collection system. Use `source: products` to create product grids — see [Collections → Products](/documentation/roe/collections#products) for the full option list.

### Basic Product Grid

````
```collection
source: products
template: grid
```
````

This creates a responsive grid (3-4 columns on desktop, 2 on tablet, 1 on mobile) with:

- Product images
- Titles (linked to product pages)
- Prices
- "Add to Cart" buttons

### Filter by Category

````
```collection
source: products
category: book
heading: Books
```
````

### Filter by Tags

````
```collection
source: products
tags: featured
limit: 6
```
````

### Control Image Display

````
```collection
source: products
aspect_ratio: portrait
category: poster
```
````

**Aspect ratio options:**

These options are provided by Roe out of the box.

- `original` - Natural sizing (default)
- `square` - (good for album covers, wallpapers)
- `portrait` - (good for books, posters)
- `tv` - 4:3
- `wide` - 16:9
- `cinema` - 21:9 (super wide)

<mark>Note:</mark> When you assign an `aspect-ratio`, this adds a CSS class to the product grid so you can target it. Any of Roe's built in themes will work without having to edit any CSS.

### Show Descriptions

````
```collection
source: products
heading: Featured Products
show_description: true
```
````

Product descriptions are truncated to ~100 characters in grids.

## Product Pages

Each published product gets a page at `/store/product-url-name`.

Product pages display:

- Breadcrumbs (`Home > Store > [Category] > Product`)
- Your Markdown content
- Any product buttons you've added via the PRODUCT button

Breadcrumbs can be disabled per-product with `breadcrumbs: false` in product/page metadata.

## `Add to Cart` Buttons

Add product add-to-cart buttons anywhere (pages/posts) using the button block syntax:

````
```button
sku: BOOK-001-THEFIRESERMON
text: Add to Cart
style: primary
```
````

**Options:**

- **sku** - Required, must match a published product
- **text** - Button text (default: "Add to Cart")
- **style** - `primary` or `secondary`
- **quantity** - Default quantity to add (default: 1)

On a product page, you can omit the SKU and it will use the current product:

````
```button
text: Buy Now
style: primary
```
````

## Store settings

The Store integrates with Snipcart.  [Setting up Snipcart to work with Roe](/documentation/roe/snipcart)

Configure your store in [Admin → Settings → store.yml](/admin/configs/store/edit):

### Currency

Set your default currency (USD, EUR, GBP, CAD, AUD, JPY). This affects:

- Price display symbols
- Product button templates
- Snipcart checkout

Make sure to add your currency to Snipcart as well under [Settings → REGIONAL SETTINGS](https://app.snipcart.com/dashboard/settings/regional): 

### Product Categories

Comma-separated list of categories for organization and SKU generation:

```
book, ebook, poster, pin, tshirt
```

When you add a new category to a Product, it will be added to this list automatically.  
<mark>Note:</mark> only use one category per Product.

### Product Button Template

Customize the Markdown template inserted by the `PRODUCT` button. Use these placeholders:

- `@image` - Product image
- `@title` - Product title
- `@price` - Formatted price with currency symbol
- `@description` - Product description
- `@sku` - Product SKU

### Snipcart Settings

- **Load Strategy** - How Snipcart loads (`on-user-interaction` recommended)
- **Modal Style** - How the cart displays when open (`side` or `full`)
- **Show Taxes** - Display taxes in cart
- **Show Quantity** - Allow quantity changes in cart

Taxes can be set up in Snipcart as needed: [Settings → TAXES](https://app.snipcart.com/dashboard/taxes)

## Order Validation

Snipcart validates orders by checking product data on your site. For this to work:

1. **Set Default Domain** - Add your Default Domain to [Admin → Settings → store.yml](/admin/configs/store/edit#default-domain)
2. **Publish Products** - In Roe, make sure your product is published so Snipcart can verify it
3. **Add Domain to Snipcart** - In your Snipcart dashboard, add your domain to allowed domains: [Domains & URLs](https://docs.snipcart.com/v3/dashboard/domains-urls)

The domain of your site has to be registered with Snipcart for this to work.

## Going Live

In order to add a Live API key to Roe, you'll need to deploy your site to a web host: [Guide → Deploy](/documentation/roe/guide-deploy)

1. **Add a credit card to Snipcart** - required to use LIVE mode.
2. **Get Live API Key** - From your Snipcart dashboard
3. **Add to Snipcart Config** - On your Live site (hosted) [Admin → Settings → snipcart.yml](/admin/snipcart_config/edit)
4. **Switch to Live Mode** - Toggle from Test to Live
5. **Configure Domain** - Set your production domain in store settings
6. **Test Checkout** - Complete a test order

Snipcart charges 2% per transaction (no monthly fee) and handles:

- Shopping cart
- Checkout flow
- Payment processing
- Order emails
- Customer management

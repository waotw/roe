---
roe_version: 0.0.20
title: Store
status: published
---

# Store

The Store feature lets you sell products directly from your site using [Snipcart](https://snipcart.com). Products are markdown files similar to pages/posts with metadata for price, SKU, images, and more.

## Quick Start

These are instructions for setting things up on the Roe side. There are instructions for setting up Snipcart on your Store edit page:

1. **Enable the Store** - Go to [Admin/Settings](/admin/configs/store/edit) and configure your store
2. **Connect Snipcart** - Add your Test Snipcart API keys in [Admin/Snipcart](/admin/snipcart_config/edit)
3. **Create Products** - Use the [Products](/admin/products) page to add items
    - Make sure to add SKUs to the Product metadata
4. **Display Products** - Use collections with `source: products` to show your catalog

## Creating Products

Products are created in the [Admin/Products](/admin/products) section. Each Product page has metadata and content:

### Metadata

The Admin will show metadata as a simple form. You can also edit the metadata directly in the file if you like.

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

#### Required Fields

- **title** - Product name
- **sku** - Unique product identifier (required for publishing)
- **price** - Price as a number (e.g., `10.00`)
- **category** - Product category (for filtering)
- **image** - Product image path
- **status** - `draft` or `published`

#### Optional Fields

- **url_name** - Custom URL (auto-generated from title if not set)
- **tags** - Tags for filtering and organization
- **description** - Short description (used in product grids)

## SKU Generator

When creating a product, you can use the SKU Generator to create standardized SKUs:

- **Book Example:** `BOOK-001-MYFIRSTBOOK`
- **Shirt Example:** `TSHIRT-001-SHIRTNAME-RED-L`
- **Suggested Pattern:** `{CATEGORY}-{NUMBER}-{TITLE/NAME}-{SPECIFIC}-{DETAILS}`

The generator:

- Uses the category and title from your Product
- Auto-increments numbers within each category
- Makes sure that the SKU is unique

## Product page and the `PRODUCT` button

Use the `PRODUCT` button in the editor to insert the product template:

**On a product page:**

- Inserts a full product card with image, title, price, description, and "Add to Cart" button
- Uses the current product's metadata automatically

**On other pages:**

- Opens a search modal to find products
- Inserts the same product template for the selected product

The product template can be customized in [Admin/Settings/store.yml](/admin/configs/store/edit).

## Displaying Products with Collections

Products work with the collection system. Use `source: products` to create product grids:

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

- `auto` - Natural sizing (default)
- `square` - 1:1 (good for album covers, wallpapers)
- `portrait` - 3:4 (good for books, posters)
- `landscape` - 4:3 (good for prints)
- `wide` - 16:9 (good for banners)

### Show Descriptions

````
```collection
source: products
show_description: true
heading: Featured Products
```
````

Product descriptions are truncated to ~100 characters in grids.

## Product Pages

Each published product gets a page at `/store/product-url-name`.

Product pages display:

- Breadcrumbs (`Home > Store > [Category] > Product`)
- Your markdown content
- Any product buttons you've added via the PRODUCT button

Breadcrumbs can be disabled per-product with `breadcrumbs: false` in product/page metadata.

## Add to Cart Buttons

Add product buttons anywhere in your markdown using the button block syntax:

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

## Store Configuration

Configure your store in [Admin/Settings/store.yml](/admin/configs/store/edit):

### Currency

Set your default currency (USD, EUR, GBP, CAD, AUD, JPY). This affects:

- Price display symbols
- Product button templates
- Snipcart checkout

Make sure to add your currency to Snipcart as well under [Settings/REGIONAL SETTINGS](https://app.snipcart.com/dashboard/settings/regional): 

### Product Categories

Comma-separated list of categories for organization and SKU generation:

```
book, ebook, poster, pin, tshirt
```

When you add a new category to a Product, it will be added to this list automatically.  
<mark>Note: only use one category per Product</mark>.

### Product Button Template

Customize the markdown template inserted by the PRODUCT button. Use these placeholders:

- `@image` - Product image
- `@title` - Product title
- `@price` - Formatted price with currency symbol
- `@description` - Product description
- `@sku` - Product SKU

### Snipcart Settings

- **Load Strategy** - How Snipcart loads (`on-user-interaction` recommended)
- **Modal Style** - Cart display style (`side` or `full`)
- **Show Taxes** - Display taxes in cart
- **Show Quantity** - Allow quantity changes in cart

Taxes can be set up in Snipcart as needed: [Settings/TAXES](https://app.snipcart.com/dashboard/taxes)

## Order Validation

Snipcart validates orders by checking product data on your site. For this to work:

1. **Set Default Domain** - Add your domain in store settings
2. **Publish Products** - Only published products can be purchased
3. **Add Domain to Snipcart** - In your Snipcart dashboard, add your domain to allowed domains

The domain of your site has to be registered with Snipcart for this to work.

## Going Live

1. **Add a credit card to Snipcart** - required to use LIVE mode.
2. **Get Live API Key** - From your Snipcart dashboard
3. **Add to Snipcart Config** - In [Admin/Snipcart](/admin/snipcart_config/edit)
4. **Switch to Live Mode** - Toggle from Test to Live
5. **Configure Domain** - Set your production domain in store settings
6. **Test Checkout** - Complete a test order

Snipcart charges 2% per transaction (no monthly fee) and handles:

- Shopping cart
- Checkout flow
- Payment processing
- Order emails
- Customer management

## Tips

**Use Categories for Organization**

- Group similar products: books, ebooks, prints, etc.
- Makes SKU generation cleaner
- Enables category-based collections

**Add Good Images**

- Products without images show a 404 placeholder
- Images are displayed at `/media/images/404.png` by default
- Upload custom images via the Media browser

**Write Good Descriptions**

- Short descriptions show in product grids
- Full content shows on product pages
- Use markdown for formatting

**Test Before Going Live**

- Use Snipcart test mode and test credit cards
- Verify order emails are working
- Check mobile responsiveness

## Related Documentation

- [Collections](/documentation/collections) - Learn about collection options

# Products & Store

Roe includes a lightweight store system for selling digital and physical products, integrated with Snipcart for checkout and payment processing.

## Architecture Overview

```
Product File
(site/products/)
      │
      ▼
┌─────────────────────────────────────┐
│   Product Model                     │
│   • Sync from file                  │
│   • Metadata + content              │
└──────────────┬──────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
      ▼                 ▼
┌──────────┐     ┌──────────────┐
│ Snipcart │     │  Collections │
│ Checkout │     │  (store page)│
│          │     │              │
│ProductButton │  │:collection{  │
│Renderer  │     │  source="    │
└──────────┘     │  products"}  │
                 └──────────────┘
```

## Product Files

Location: `site/products/`

### File Format

```markdown
---
title: "My Digital Book"
slug: "my-digital-book"
price: 29.99
sku: BOOK-001
currency: USD
image: media/images/book-cover.jpg
files:
  - url: media/files/book.pdf
    label: "PDF Version"
  - url: media/files/book.epub
    label: "EPUB Version"
paid: true
---

Product description in Markdown...

## Features

- Feature 1
- Feature 2

## What's Included

- PDF (300 pages)
- EPUB (e-reader compatible)
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `title` | String | Product name |
| `slug` | String | URL-friendly identifier |
| `price` | Number | Price (e.g., 29.99) |
| `sku` | String | Unique stock keeping unit |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `currency` | String | 3-letter code (default: site currency) |
| `image` | String | Path to product image |
| `files` | Array | Downloadable files after purchase |
| `paid` | Boolean | If true, requires checkout |
| `weight` | Number | Shipping weight (physical products) |
| `dimensions` | Hash | `{length, width, height}` |
| `inventory` | Number | Stock count (optional tracking) |

## Product Model

File: `app/models/product.rb`

### Key Methods

```ruby
# Create/update from file
def self.create_or_update_from_file(path)
  frontmatter = YAML.safe_load(File.read(path))
  
  product = find_or_initialize_by(slug: frontmatter['slug'])
  product.assign_attributes(frontmatter)
  product.content = extract_content(path)
  product.save!
end

# Sync all products
def self.sync_all
  Dir.glob('site/products/*.md').each do |path|
    create_or_update_from_file(path)
  end
end

# Instance methods
def formatted_price
  "$#{price}"
end

def paid?
  price > 0
end

def digital?
  files.any?
end
```

## Snipcart Integration

File: `app/models/snipcart_config.rb`

### Configuration

```yaml
# site/system/features/store.yml
enabled: true
api_key: "..."  # Public Snipcart API key
```

### Product Button Renderer

File: `app/services/product_button_renderer.rb`

```ruby
class ProductButtonRenderer
  def self.render(product)
    <<~HTML
      <button class="snipcart-add-item"
              data-item-id="#{product.sku}"
              data-item-price="#{product.price}"
              data-item-url="#{product.url}"
              data-item-description="#{product.title}"
              data-item-image="#{product.image}"
              data-item-name="#{product.title}">
        Add to Cart - #{product.formatted_price}
      </button>
    HTML
  end
end
```

### Usage in Templates

```erb
<%= ProductButtonRenderer.render(@product) %>
```

Renders:

```html
<button class="snipcart-add-item"
        data-item-id="BOOK-001"
        data-item-price="29.99"
        data-item-url="/products/my-digital-book"
        data-item-description="My Digital Book"
        data-item-image="/media/images/book-cover.jpg"
        data-item-name="My Digital Book">
  Add to Cart - $29.99
</button>
```

## Store Page

### Collection Syntax

Create a store page listing all products:

```markdown
---
title: "Store"
slug: "store"
---

Browse my products:

:collection{source="products" template="full"}
```

### Product Display Templates

| Template | Description |
|----------|-------------|
| `full` | Large image, full description |
| `compact` | Small image, title + price |
| `list` | Row layout, minimal |
| `links` | Text-only list |

### Custom Store Layout

```markdown
## Featured Products

:collection{source="products" tags="featured" limit="3" template="full"}

## All Products

:collection{source="products" order="newest" template="compact"}
```

## Product Categories

Use tags to categorize products:

```yaml
---
title: "T-Shirt"
slug: "t-shirt"
price: 25.00
sku: APPAREL-001
tags:
  - apparel
  - clothing
  - featured
---
```

Filter in collections:

```markdown
:collection{source="products" tags="apparel"}
```

## Checkout Flow

1. **Browse**: Customer views products on store page
2. **Add to Cart**: Click Snipcart button
3. **Cart Sidebar**: Snipcart overlay shows cart contents
4. **Checkout**: Snipcart handles payment form
5. **Success**: Snipcart redirects to success page
6. **Webhooks**: Roe receives order confirmation
7. **Delivery**: Digital files emailed or displayed on thank you page

## Webhook Handling

File: `app/controllers/webhooks_controller.rb`

```ruby
def snipcart
  case params['eventName']
  when 'order.completed'
    handle_order_completed
  end
  
  head :ok
end

def handle_order_completed
  order = params['content']
  
  order['items'].each do |item|
    product = Product.find_by(sku: item['id'])
    member = Member.find_by(email: order['email'])
    
    # Grant access to digital products
    if product&.digital?
      send_digital_files(member, product)
    end
  end
end
```

## Digital Product Delivery

### Email Delivery

Send download links via email:

```ruby
def send_digital_files(member, product)
  MemberMailer.digital_purchase(
    member: member,
    product: product,
    files: product.files
  ).deliver_later
end
```

### Thank You Page

Create a custom thank you page with download links:

```markdown
---
title: "Thank You!"
slug: "thank-you"
---

## Your Purchase

<% if @order %>
  <% @order.products.each do |product| %>
    ### <%= product.title %>
    
    <% product.files.each do |file| %>
      - [Download <%= file.label %>](<%= file.url %>)
    <% end %>
  <% end %>
<% end %>
```

## Admin Interface

### Products List

**Admin → Products:**

- List all products with price and inventory
- Filter by published status
- Quick actions: Edit, View, Duplicate

### Product Editor

**Admin → Products → Edit:**

- Title, slug, SKU
- Price and currency
- Upload image (with media picker)
- Description (Markdown editor)
- File attachments
- Tags and categories

### Sync Products

Button to manually sync products from files:

```ruby
# Admin::ProductsController#sync
def sync
  Product.sync_all
  redirect_to admin_products_path, notice: "Products synced"
end
```

## Collections Integration

Products work with the collections system:

```markdown
<!-- Recent products -->
:collection{source="products" order="newest" limit="5"}

<!-- Featured products -->
:collection{source="products" tags="featured" template="full"}

<!-- All products sorted by price -->
:collection{source="products" sort="price" sort_dir="asc"}
```

## Configuration

Enable store in `site/system/features/store.yml`:

```yaml
enabled: true
api_key: "YOUR_SNIPCART_PUBLIC_KEY"
```

Add Snipcart JavaScript to your theme:

```html
<!-- In layout/navigation.md or theme -->
<script src="https://cdn.snipcart.com/themes/v3.0.31/default/snipcart.js"></script>
<link rel="stylesheet" href="https://cdn.snipcart.com/themes/v3.0.31/default/snipcart.css" />
<div hidden id="snipcart" data-api-key="{{site.store.snipcart_api_key}}"></div>
```

## Testing

### Test Mode

Use Snipcart test API key:

```yaml
development:
  api_key: "MzMxN2Y0ODMtOWNiMy00YzUzLWFiNTYtZjMwZTRkZDcxYzM4NjM3OTIyMzU3NjQwOTkzMDM5"
```

### Test Card

| Field | Value |
|-------|-------|
| Card Number | `4242 4242 4242 4242` |
| Expiry | Any future date |
| CVC | Any 3 digits |

## Best Practices

### Product Images

- Use square images (1:1 ratio)
- Minimum 800x800px
- Consistent style across products
- Show product in use/context

### Pricing

- Use psychological pricing ($29 vs $30)
- Consider tiered pricing for digital bundles
- Offer discounts for members
- Display currency clearly

### Descriptions

- Lead with benefits, not features
- Include specifications in bullet points
- Use product images in description
- Add testimonials if available

### Inventory (Physical Products)

Track inventory manually or via Snipcart:

```yaml
---
inventory: 100
low_stock_threshold: 10
---
```

## Related

- [Payments & Stripe](./12-payments-stripe.md) - Alternative payment processor
- [Collections](./03-collections.md) - Displaying products
- [Configuration](./06-configuration.md) - Feature flags
- [Content System](./02-content-system.md) - Product file format

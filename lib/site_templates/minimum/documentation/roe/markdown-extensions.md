---
title: "Markdown Extensions"
post_type: documentation
status: unlisted
---

# Markdown Extensions

Roe provides a number of custom Markdown extensions that allow you to create rich content beyond standard Markdown.

### Products

| Option | Required | Description |
|--------|----------|-------------|
| `show_description` | No | Show truncated product description (~100 chars) below the title |
| `groups` | No | `enabled` to group variants together (e.g., Paperback/Hardback/Ebook of same book) |
| `aspect_ratio` | No | Image aspect ratio: `auto` (default), `portrait`, `square`, or `landscape` |

**Notes:**
- When `groups: enabled`, the grid uses the **primary** variant's image and links to the primary variant's page
- Variant names appear in parentheses below the title (e.g., `(Paperback, Hardback)`)
- Price display for grouped products is controlled by your **store config** (`site/system/features/store.yml`):
  - `price_display: range` — shows `$10.00 - $25.00` (default)
  - `price_display: lowest` — shows `$10.00`
  - `price_display: highest` — shows `$25.00`
  - `price_separator` — custom separator between range prices (default: `-`)
- `button_text` in store config controls the "View" button text for grouped products (no button renders if left blank)
- Individual products show "Add to Cart" button directly in the grid
The product-specific options are:
- show_description (boolean-ish: "true" or true)
- groups ("enabled" or true)
- aspect_ratio (string, defaults to "auto")
Everything else (pricing behavior, button text, grouping logic) is controlled at the store config level in site/system/features/store.yml, not at the collection level.

## Cards

Cards are special content blocks that you can place within your Markdown.

### Pullquote Card

Pullquotes are stylized quotes that can be positioned in different ways.

```markdown
```card
type: pullquote
text: Your quote text here
attribution: Author Name
position: center
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `pullquote` |
| `text` | Yes | The quote content |
| `attribution` | No | Who said it — displays with em-dash |
| `position` | No | `center` (default), `left`, or `right` — floating positions wrap with body text |

**Merge with body text:** Use `||` in your paragraph after a left/right pullquote to split the text around it, or let it auto-split.

### Aside Card

Asides are supplementary content blocks that can include images, text, and links.

```markdown
```card
type: aside
text: Text content
image: /media/images/photo.jpg
link: https://example.com
link_text: Read more
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `aside` |
| `text` | No | Body text |
| `image` | No | Path to image — displays above text |
| `link` | No | URL to link to |
| `link_text` | No | Custom link text — if omitted, shows arrow appended to text |

**Image-only:** Set image with no text or link_text for image-only aside.

### Post Link Card

Post links are cards that reference other posts or external URLs.

```markdown
```card
type: post-link
post: my-post-url-name
style: small
title: Override Title
subtitle: Override Subtitle
excerpt: Override excerpt
image: /media/images/override.jpg
author: Override Author
date: 2024-01-01
url: https://example.com
link_text: Custom CTA
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `post-link` |
| `post` | No | Reference a post by its url_name — auto-populates all fields |
| `style` | No | `small` (default), `medium`, or `large` |
| `title` | No | Override or provide custom title |
| `subtitle` | No | Override subtitle (medium/large only) |
| `excerpt` | No | Override excerpt (medium/large only) |
| `image` | No | Override image path, or set to `none` to hide image |
| `author` | No | Override author — falls back to site author |
| `date` | No | Override date |
| `url` | No | Custom URL if not using `post` reference |
| `link_text` | No | Custom call-to-action text — defaults to "Read full story →" |

**Auto-population priority:** When using `post:`, the referenced post's metadata fills all fields, then your explicit overrides apply.

## Collections

Collections display lists of content from your site.

```markdown
```collection
source: posts
order: date
limit: 10
template: list
heading: Latest Posts
tags: featured, -draft
related: false
```
```

### Source & Filtering

| Option | Required | Description |
|--------|----------|-------------|
| `source` | No | `posts` (default), `pages`, `documentation`, or `products` |
| `tags` | No | Comma-separated, use `-tag` to exclude |
| `category` | No | Filter products by category |
| `podcast` | No | Filter posts by podcast key |
| `post_type` | No | Filter posts by type: `article`, `audio`, `video`, or `podcast` |
| `related` | No | `true` shows items linked via frontmatter `related:` — bidirectional |

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

## Galleries

### Auto-Galleries

Consecutive images automatically become galleries:

```markdown
![alt1](/media/images/photo1.jpg)
![alt2](/media/images/photo2.jpg)
![alt3](/media/images/photo3.jpg)
```

→ Becomes a 3-column gallery automatically.

### Manual Gallery

```markdown
```gallery
![alt1](/media/images/photo1.jpg)
![alt2](/media/images/photo2.jpg)
![alt3](/media/images/photo3.jpg)
```
```

### With Captions

```markdown
![alt text](/media/images/photo.jpg)(*Caption text in asterisks*)
```

**Features:**
- Auto-responsive: 1, 2, or 3 columns based on image count
- Responsive images with srcset
- Blank lines separate gallery rows
- Captions supported with `(*Caption*)` syntax after image

## Forms

Forms provide interactive elements for memberships and payments.

### Signup

```markdown
```form
for: signup
button-text: Sign Up
upgrade-button-text: Upgrade now
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `signup` |
| `button-text` | No | Primary button text — default "Sign Up" |
| `upgrade-button-text` | No | Optional second button for immediate upgrade |

### Signin

```markdown
```form
for: signin
button-text: Send Magic Link
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `signin` |
| `button-text` | No | Button text — default "Send Magic Link" |

### Checkout

```markdown
```form
for: checkout
member-button-text: Upgrade
non-member-button-text: Sign up to upgrade
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `checkout` |
| `member-button-text` | No | For logged-in members |
| `non-member-button-text` | No | For non-members (shows sign-up link) |

### Donate

```markdown
```form
for: donate
button-text: Donate
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `donate` |
| `button-text` | No | Button text — default "Donate" |

Uses donation amounts from members.yml config.

### Unsubscribe

```markdown
```form
for: unsubscribe
button-text: Unsubscribe
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `unsubscribe` |
| `button-text` | No | Button text — default "Unsubscribe" |

### Paid Content (Paywall)

```markdown
```form
for: paid_content
text: This is premium content. Upgrade to continue reading.
button-text: Become a paid member
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `paid_content` |
| `text` | No | Message shown above upgrade button |
| `button-text` | No | CTA text — default "Become a paid member" |

## Buttons (Store/Products)

Buttons allow you to add product purchase buttons to your content.

```markdown
```button
sku: PRODUCT-SKU
text: Add to Cart
style: primary
quantity: 1
```
```

| Option | Required | Description |
|--------|----------|-------------|
| `sku` | No | Product SKU — auto-detects on product pages if omitted |
| `text` | No | Button text — default "Add to Cart" |
| `style` | No | `primary` (default), `secondary`, or `outline` |
| `quantity` | No | Default quantity — default 1 |

### Variant Lists

Place multiple button blocks consecutively (no blank lines) to render as a variant selector list with prices:

```markdown
```button
sku: book-paperback
```
```button
sku: book-hardcover
```
```button
sku: book-ebook
```
```

**Auto-variant detection:** Products with `group:` metadata automatically show all variants in the group as a list with a single button.

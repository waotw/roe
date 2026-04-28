# Configuration

Configuration files live in `site/system/` and are synced into the database for fast access.

## Configuration Files

```
site/system/
├── site.yml           # Main site configuration
└── defaults/
    ├── cards.yml      # Card type defaults
    └── collections.yml # Collection defaults
```

## site.yml

Main site configuration synced to `SiteConfig` table.

```yaml
title: My Site
description: A brief description for SEO
author: Your Name
favicon: /media/images/favicon.ico
url: https://example.com

fonts:
  heading:
    family: NewsReader
    regular: Newsreader_36pt-Medium.ttf
    bold: Newsreader_60pt-Bold.ttf
  body:
    family: Source Serif
    regular: SourceSerif4_18pt-Regular.ttf
    bold: SourceSerif4_48pt-Bold.ttf
    italic: SourceSerif4_18pt-Italic.ttf
    bold_italic: SourceSerif4_18pt-BoldItalic.ttf
  mono:
    family: Berkeley Mono
    regular: BerkeleyMono-Regular.woff2
    bold: BerkeleyMono-Bold.woff2

feeds:
  enabled: true
  rss_title: My Site RSS
  atom_title: My Site Atom
  description_mode: first_paragraph
  show_content: false

navigation:
  collections:
    - source: posts
      post_type: article
      heading: Articles
    - source: posts
      post_type: music
      heading: Music

static:
  enabled: false
  base_url: https://example.com

metadata:
  og_image: /media/images/og-default.jpg
  twitter_card: summary_large_image
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Site title |
| `description` | string | Default meta description |
| `author` | string | Default author for posts |
| `favicon` | string | Favicon path |
| `url` | string | Production URL |
| `feeds` | object | RSS/Atom feed settings |
| `navigation` | object | Navigation configuration |
| `static` | object | Static generation settings |
| `metadata` | object | Social sharing defaults |

### Fonts Configuration

Fonts are served via `FontsController`. Font files go in `site/system/assets/fonts/`.

```yaml
fonts:
  heading:
    family: Font Name
    regular: path/to/Regular.ttf
    bold: path/to/Bold.ttf
    italic: path/to/Italic.ttf  # optional
    bold_italic: path/to/BoldItalic.ttf  # optional
```

### Feed Configuration

```yaml
feeds:
  enabled: true
  rss_title: "Site RSS Feed"
  atom_title: "Site Atom Feed"
  description_mode: first_paragraph  # or: full, excerpt, none
  show_content: false  # true = include full content
```

### Navigation Configuration

```yaml
navigation:
  collections:
    - source: posts
      post_type: article
      heading: Articles
      tags: [featured]  # optional filter
    - source: pages
      heading: About
```

---

## cards.yml

Default settings for card types. Define defaults that apply when not specified inline.

```yaml
post-link:
  default_image: /media/images/default-post-link.jpg
  default_style: small
  default_link_text: "Read full story →"

aside:
  default_link_text: "→"

pullquote:
  default_position: center
```

### Card Type Defaults

| Card Type | Default Fields |
|-----------|----------------|
| `post-link` | `default_image`, `default_style`, `default_link_text` |
| `aside` | `default_link_text` |
| `pullquote` | `default_position` |

---

## collections.yml

Default settings for inline collections.

```yaml
default_source: posts
default_post_type: all
default_order: date
default_limit: "10"
default_template: list
items_per_page: "20"
button_template: |-
  heading: __PLACEHOLDER__
  limit: 5
  post_type: all
  template: list
```

### Fields

| Field | Default | Description |
|-------|---------|-------------|
| `default_source` | `posts` | Source when not specified in inline collection |
| `default_post_type` | `all` | Post type filter when not specified |
| `default_order` | `date` | Sort order when not specified |
| `default_limit` | `10` | Item limit when not specified |
| `default_template` | `list` | Template when not specified |
| `items_per_page` | `20` | Pagination size |
| `button_template` | — | Template for "Show More" links |

### Button Template

The `button_template` uses `__PLACEHOLDER__` which is replaced with the collection's heading:

```yaml
button_template: |-
  heading: __PLACEHOLDER__
  limit: 5
  post_type: all
  template: list
```

---

## Accessing Configuration

### From Ruby

```ruby
# Get site.yml value
SiteConfig.get(:title)
SiteConfig.get(:feeds, :enabled)

# Get defaults
SiteConfig.default(:cards, :pullquote, :default_position)
```

### From Views

```erb
<%= SiteConfig.get(:title) %>
<%= SiteConfig.get(:feeds, :rss_title) %>
```

### From Models

```ruby
class Post < ApplicationRecord
  include HasMetadata
  
  def feed_description
    mode = SiteConfig.get(:feeds, :description_mode)
    # "first_paragraph", "full", "excerpt", "none"
  end
end
```

---

## Auto-Generation

If config files are missing on startup, `ConfigGenerator` (`app/services/config_generator.rb`) creates them with sensible defaults.

This allows the app to spin up with all configuration prepared.

---

## Related

- [Architecture](./01-architecture.md) - How config fits into the system
- [Collections](./03-collections.md) - Inline collection parameters
- [Markdown Extensions](./04-markdown-extensions.md) - Card types
- [Members & Authentication](./11-members-authentication.md) - Member feature configuration
- [Payments & Stripe](./12-payments-stripe.md) - Stripe configuration
- [Podcasts](./13-podcasts.md) - Podcast configuration
- [Email & Newsletters](./14-email-newsletters.md) - Postmark configuration
- [Products & Store](./16-products-store.md) - Store and Snipcart configuration

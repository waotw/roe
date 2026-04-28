# Roe Documentation

Complete developer documentation for Roe, a file-first CMS with first-class support for podcasts, paid memberships, newsletters, and a built-in store.

## Quick Start

New to Roe? Start here:

1. **[Architecture Overview](./01-architecture.md)** - Understand the system design
2. **[Content System](./02-content-system.md)** - How content is stored and managed
3. **[Configuration](./06-configuration.md)** - Set up your site

## Documentation by Topic

### Core Concepts

| Doc | Description |
|-----|-------------|
| [01 - Architecture](./01-architecture.md) | System design, data flow, key principles |
| [02 - Content System](./02-content-system.md) | Markdown files, YAML frontmatter, status system |
| [03 - Collections](./03-collections.md) | Grouping and displaying content |
| [04 - Markdown Extensions](./04-markdown-extensions.md) | Cards, galleries, pullquotes |
| [05 - Sync & Generation](./05-sync-generation.md) | Content sync, static site generation |

### Configuration & Admin

| Doc | Description |
|-----|-------------|
| [06 - Configuration](./06-configuration.md) | site.yml, fonts, navigation |
| [07 - Admin UI](./07-admin-ui.md) | Admin interface features and workflows |
| [08 - Routes](./08-routes.md) | Public and admin route structure |
| [10 - Tooltips](./10-tooltips.md) | Help tooltip component for admin |

### Paid Features & Membership

| Doc | Description |
|-----|-------------|
| [11 - Members & Authentication](./11-members-authentication.md) | Magic-link auth, member lifecycle, access control |
| [12 - Payments & Stripe](./12-payments-stripe.md) | Stripe integration, subscriptions, checkout |
| [13 - Podcasts](./13-podcasts.md) | Podcast feeds, RSS, private feeds |
| [14 - Email & Newsletters](./14-email-newsletters.md) | Postmark integration, broadcasts |
| [16 - Products & Store](./16-products-store.md) | Store catalog, Snipcart integration |

### Import & Integration

| Doc | Description |
|-----|-------------|
| [15 - Substack Importer](./15-substack-importer.md) | Multi-phase content import |
| [17 - Media System](./17-media-system.md) | Image variants, responsive images, media handling |

### Development & Operations

| Doc | Description |
|-----|-------------|
| [09 - Extending Roe](./09-extending.md) | Adding cards, extensions, content types |
| [18 - Troubleshooting](./18-troubleshooting.md) | Common issues and solutions |
| [19 - Testing](./19-testing.md) | Test conventions and best practices |
| [20 - Deployment](./20-deployment.md) | Production deployment guide |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         CONTENT SOURCE                          │
│                     (site/ directory)                           │
│  posts/  pages/  documentation/  products/  media/  system/     │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CONTENT SYNC SERVICE                       │
│                (ContentSync, ContentWatcher)                    │
│  • File watching in development                                 │
│  • Sync to SQLite on startup                                    │
│  • Handles renames and deletions                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
           ┌──────────────┼───────────────┐
           ▼              ▼               ▼
┌─────────────────┐ ┌─────────────┐ ┌──────────────────┐
│   ADMIN UI      │ │ PUBLIC SITE │ │ STATIC GENERATOR │
│ (Members,       │ │ (Dynamic    │ │ (Pre-rendered    │
│  Podcasts,      │ │  rendering) │ │  output)         │
│  Store)         │ │             │ │                  │
└─────────────────┘ └─────────────┘ └──────────────────┘
```

## Key Features

### File-First CMS
- Content lives as Markdown files with YAML frontmatter
- Database is a cache, not the source of truth
- Edit via admin UI or directly in the file system

### Podcast Support
- RSS feed generation (public and private)
- Per-member token authentication for private feeds
- Auto-seed from existing RSS feeds

### Paid Memberships
- Stripe integration for subscriptions
- Magic-link authentication (no passwords)
- Content gating by membership level

### Static Generation
- Pre-render entire site to `/public`
- Incremental regeneration on changes
- Perfect for CDN deployment

## Common Tasks

### Adding a New Post
1. Create file in `site/posts/YYYY-MM-DD-slug.md`
2. Add YAML frontmatter with `title`, `date`, `post_type`
3. Write content in Markdown
4. Save - ContentSync will pick it up automatically

### Configuring the Site
1. Edit `site/system/global/site.yml`
2. Changes sync immediately in development
3. Use admin UI for validation and field help

### Adding a Podcast
1. Go to Admin → Config → Podcast
2. Configure feed settings
3. Optional: Use "Seed from RSS" to import existing feed
4. Create posts with `post_type: podcast`

### Running Imports
1. Admin → Imports
2. Upload Substack export ZIP
3. Follow 3-phase import process
4. Review imported content before publishing

## File Locations Quick Reference

| Component | Location |
|-----------|----------|
| Content files | `site/posts/`, `site/pages/`, `site/documentation/` |
| Configuration | `site/system/` |
| Media uploads | `site/media/` |
| Email templates | `site/emails/` |
| Layout components | `site/layout/` |
| Services | `app/services/` |
| Admin controllers | `app/controllers/admin/` |
| Models | `app/models/` |

## Related Resources

- [AGENTS.md](../AGENTS.md) - AI agent instructions and project conventions
- [README.md](../README.md) - Project overview and setup
- [Gemfile](../Gemfile) - Dependencies

## Contributing to Documentation

When adding new features:

1. Update the relevant docs file (or create new one)
2. Add cross-references in "Related" sections
3. Include code examples where helpful
4. Follow the numbered naming convention for new docs
5. Update this index

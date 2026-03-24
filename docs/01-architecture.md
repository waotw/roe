# Architecture Overview

Roe is a file-first CMS where the file system is the source of truth. Content lives as Markdown files with YAML frontmatter. A sync system pulls content into SQLite for querying, and a static generator outputs HTML pages.

```
┌─────────────────────────────────────────────────────────────────┐
│                         CONTENT SOURCE                          │
│                     (site/ directory - Markdown files)          │
│  posts/  pages/  documentation/  layout/  media/  system/       │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CONTENT SYNC SERVICE                       │
│                (app/services/content_sync.rb)                   │
│  • Reads files on startup or file change                        │
│  • Parses frontmatter + markdown content                        │
│  • Upserts into SQLite (Post, Page, Documentation tables)       │
│  • Handles renames via basename matching                        │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                         DATABASE (SQLite)                       │
│                   (db/schema.rb - cache layer)                  │
│  posts, pages, documentation, media, site_configs, users        │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────────┐ ┌─────────────┐ ┌──────────────────┐
│   ADMIN UI      │ │ PUBLIC SITE │ │ STATIC GENERATOR │
│ (Rails + Turbo) │ │ (Rails)     │ │ (Static output)  │
└─────────────────┘ └─────────────┘ └──────────────────┘
```

## Key Principles

### 1. File System as Source of Truth
- Edit content via admin UI (writes to files) or directly in the `site/` directory
- Database is a cache for fast queries
- Never edit the database directly

### 2. Two Rendering Paths
- **Dynamic**: Rails renders markdown on-demand using `HasMarkdownExtensions#to_html`
- **Static**: `StaticGenerator` pre-renders all pages to `/public`

### 3. Sync on Startup, Watch in Dev
- `ContentSync.sync_all` runs on server boot (`config/initializers/content_management.rb`)
- `ContentWatcher` monitors file changes in development (`app/services/content_watcher.rb`)
- Changes trigger incremental static regeneration if enabled

### 4. Metadata as JSON
- Frontmatter parsed and stored as JSON in `metadata` column
- `HasMetadata` concern provides dynamic attribute access (`post.title`, `post.tags`)
- Queries filter using SQLite JSON functions

## Core Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ContentSync | `app/services/content_sync.rb` | File → Database sync |
| ContentWatcher | `app/services/content_watcher.rb` | Dev file monitoring |
| StaticGenerator | `app/services/static_generator.rb` | HTML output generation |
| HasMarkdownExtensions | `app/models/concerns/has_markdown_extensions.rb` | Markdown → HTML pipeline |
| HasMetadata | `app/models/concerns/has_metadata.rb` | JSON metadata access |

## Data Flow: Content Edit

```
1. User edits post in admin UI
2. AdminPostsController#update writes to site/posts/file.md
3. ContentWatcher detects change
4. ContentSync syncs file to Post record
5. If static mode: StaticGenerator regenerates affected pages
6. Public site reflects new content
```

## Data Flow: Static Generation

```
1. rake task or admin button triggers generation
2. StaticGenerator loads all Post, Page, Documentation records
3. Each record calls #to_html (HasMarkdownExtensions)
4. Output written to public/{path}.html
5. Collections, feeds, indexes all generated
6. Assets copied from site/system/assets/ and site/media/
```

## Configuration Hierarchy

```
site/system/site.yml           → SiteConfig table → SiteConfig.get(key)
site/system/defaults/cards.yml → Default card settings
site/system/defaults/collections.yml → Collection defaults
```

See [Configuration](./06-configuration.md) for details.

## Extension Points

- **Card types**: Add to `HasMarkdownExtensions#render_card` + `StaticGenerator`
- **Markdown extensions**: Add regex processors in `HasMarkdownExtensions#to_html`
- **Collection templates**: Add to `CollectionRenderer` + static generator

See [Extending](./09-extending.md) for details.

# Content Sync & Static Generation

Roe has two mechanisms for keeping content in sync: runtime file watching (development) and static site generation (production).

## Content Sync

### How It Works

The `ContentSync` service (`app/services/content_sync.rb`) reads Markdown files and upserts them into the database.

```
site/posts/hello.md + frontmatter → Post record
site/pages/about.md + frontmatter → Page record
```

### Sync Triggers

| Trigger | Location | What Happens |
|---------|----------|---------------|
| Server startup | `config/initializers/content_management.rb` | Full sync (`sync_all`) |
| File change | `app/services/content_watcher.rb` | Incremental sync |
| Admin UI save | `AdminPostsController#update` | File write triggers watcher |
| Manual rake | `lib/tasks/content.rake` | Full or targeted sync |

### Sync Process

```ruby
ContentSync.sync_all
# 1. sync_site_config       → SiteConfig table
# 2. sync_defaults          → cards.yml, collections.yml
# 3. sync_posts             → site/posts/**/*.md
# 4. sync_pages             → site/pages/**/*.md
# 5. sync_documentation     → site/documentation/**/*.md
```

### File Watching (Development)

The `ContentWatcher` (`app/services/content_watcher.rb`) monitors these directories:

- `site/posts`
- `site/pages`
- `site/documentation`
- `site/system`
- `site/media`

Uses the `listen` gem for efficient file system events.

### Rename Detection

When a file is removed and another added with a similar name, the system attempts to match them:

```ruby
# removed: "site/posts/old-name.md"
# added: "site/posts/new-name.md"

# Detected as rename → updates file_path, preserves ID
```

Matching logic (lines 162-198):
- Same basename prefix/suffix
- Date prefix variations (`01-`, `2024-01-01-`)

### Orphan Handling

Records without matching files are either:
1. Renamed files (if match found)
2. Destroyed (if no match found)

---

## Static Site Generation

### Overview

The `StaticGenerator` (`app/services/static_generator.rb`) pre-renders all pages to `public/` for hosting on any static server or CDN.

### Output Structure

```
public/
├── index.html
├── about.html
├── posts/
│   ├── index.html
│   ├── page-2.html
│   ├── hello-world.html
│   └── tech/
│       └── new-framework.html
├── documentation/
│   ├── index.html
│   └── getting-started.html
├── collections/
│   ├── ruby.html
│   └── type-article.html
├── feed.rss
├── feed.atom
└── assets/  (copied from site/system/assets/)
```

### Generation Process

```ruby
StaticGenerator.generate
# 1. Load manifest (last build state)
# 2. Determine what changed
# 3. Regenerate affected pages
# 4. Copy changed assets
# 5. Save new manifest
```

### Change Detection

The manifest (`public/.manifest.json`) tracks file timestamps:

```json
{
  "generated_at": "2026-03-22T20:48:30.856227Z",
  "posts": {
    "1": { "updated_at": "2026-03-22T20:45:00Z", "html_file": "posts/slug.html" }
  },
  "configs": { "site": "...", "defaults/collections": "..." },
  "layouts": { "/path/to/nav.md": 1234567890 },
  "assets": { "fonts": {...}, "images": {...} }
}
```

**Incremental builds:**
- Config/layout change → full regeneration
- Post change → regenerate that post + related collections + feeds
- Asset change → copy only changed files

### Triggering Generation

| Method | Command/Action |
|--------|----------------|
| Rake task | `rails content:sync` |
| Rake task | `rails static_site:generate` |
| Admin UI | "Generate Static Site" button |
| File watcher | `ContentWatcher` (if `static_on_change: true`) |

### Markdown Processing During Generation

Each content record calls `to_html` during static generation, which runs the full [Markdown Extensions pipeline](./04-markdown-extensions.md):

1. Code blocks protected
2. Galleries processed
3. Collections rendered (queries database)
4. Cards rendered
5. Kramdown conversion
6. Pullquotes merged with paragraphs

**Important:** The static generator must be updated when adding new Markdown extensions or card types. See [Extending](./09-extending.md).

---

## Initialization Flow

When the Rails server starts (`config/initializers/content_management.rb`):

```ruby
# 1. Generate default configs if missing
ConfigGenerator.generate_all

# 2. Generate default pages if missing
PageGenerator.generate_defaults

# 3. Sync content from files to database
ContentSync.sync_all

# 4. Start file watcher (development only)
ContentWatcher.start if Rails.env.development?
```

---

## Static Mode Configuration

In `site/system/site.yml`:

```yaml
static:
  enabled: true
  static_on_change: false  # Auto-regenerate on file changes
  base_url: https://example.com
```

---

## Related

- [Content System](./02-content-system.md) - File format and frontmatter
- [Collections](./03-collections.md) - Collection rendering
- [Markdown Extensions](./04-markdown-extensions.md) - Card and gallery processing
- [Extending](./09-extending.md) - What to update when adding features
- [Media System](./17-media-system.md) - Media handling during sync and generation
- [Deployment](./20-deployment.md) - Production deployment of static sites

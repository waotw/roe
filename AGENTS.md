# AGENTS.md

## Overview

Roe is a Rails 8.1 file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store. Content (posts, pages, documentation, products) is authored as Markdown files in `site/` and synced to SQLite via `ContentSync`. The app can also generate a fully static version of the public site. Ruby 3.2.2.

**Architecture**: Roe uses a **versioned directory structure** that supports seamless updates without touching user content. The Rails application lives in `current/`, while user content remains in `site/` at the root level.

**Repository**: Primary development happens at [Codeberg](https://codeberg.org/waotw/roe) (migrated from Sourcehut).

Primary integrations: **Stripe** (payments / paid memberships), **Postmark** (transactional + broadcast email, with a fallback to ActionMailer when unconfigured), and a multi-phase **Substack importer**.

## Directory Structure

Roe uses a **versioned directory structure** to support seamless updates:

```
/roe/                             # Project root
  current/                        # Current Roe version (Rails app)
    app/
    bin/
    config/
    .git/                         # Git repository
    ...
  site/                           # Your content (persistent)
    posts/
    pages/
    media/
    db/
    ...
  staging/                        # Transient — only present mid-update
  static_site/                    # Generated static site output
  site_backups/                   # Automatic backups
  roe.sh                          # Server management script
  VERSION                         # Current version info
```

### Working with the Structure

**Git commands** - Run from `current/` directory:
```bash
cd current
git status
git add .
git commit -m "message"
```

**Rails commands** - Can run from root using `roe.sh`:
```bash
./roe.sh start       # Start server
./roe.sh console     # Rails console
./roe.sh restart     # Restart server
```

Or manually from `current/`:
```bash
cd current && bin/rails server
cd current && bin/rails console
```

**Content editing** - Edit files directly in `site/` at root level:
```bash
vi site/posts/my-post.md
```

## Build / Run / Test Commands

```bash
# Setup
bin/setup                         # Install deps, generate master.key, create site structure, prepare DB, sync content, bootstrap admin

# Run dev server (from root)
./roe.sh start                    # Start server (recommended)
# OR from current/
cd current && bin/dev             # Starts Puma + Tailwind watcher

# Run all tests
cd current && bin/rails test

# Run a single test file
cd current && bin/rails test test/models/post_test.rb

# Run a single test by name
cd current && bin/rails test -n test_should_get_index

# Run a single test by line number
cd current && bin/rails test test/controllers/posts_controller_test.rb:4

# Lint
cd current && bin/rubocop                       # RuboCop (rubocop-rails-omakase style)
cd current && bin/rubocop -A                    # Auto-correct

# Security
cd current && bin/brakeman                      # Static security analysis
cd current && bin/bundler-audit                 # Check gems for known vulnerabilities

# Database
cd current && bin/rails db:migrate
cd current && bin/rails db:seed

# Content / site tasks
cd current && bin/rails content:sync            # Sync site/ files into DB
cd current && bin/rails content:watch           # Watch site/ for changes (dev)
cd current && bin/rails images:generate_variants
cd current && bin/rails static_site:build       # Generate static HTML (outputs to root static_site/)
cd current && bin/rails media_reference:rebuild # Rebuild MediaReference join table

# Update system
cd current && bin/rails site:backup             # Backup production site
```

## Project Structure

```
current/                          # Rails application (versioned)
  app/
    controllers/
      admin/                        # Admin::BaseController-rooted backend
      members/                      # Member-facing auth + account
      system/                       # Theme/font/image asset serving
      webhooks/                     # Postmark + Stripe webhook receivers
      *.rb                          # Public site controllers
    models/
      concerns/                     # HasMetadata, HasMarkdownExtensions,
                                    # HasInlineFootnotes, HasAudience
      *.rb                          # Post, Page, Documentation, Medium,
                                    # Member, Product, User, Session,
                                    # SiteConfig, PodcastConfig,
                                    # PostmarkConfig, StripeConfig,
                                    # SnipcartConfig, SyncConfig, DeploySecrets,
                                    # Import, NewsletterSend,
                                    # MediaReference, Current, UpdateStatus
    services/
      roe_updater/                  # Staged update system
        version_checker.rb
        backup_manager.rb
        downloader.rb
        migration_tester.rb
        switch_manager.rb
        update_orchestrator.rb
      substack_importer/            # Multi-phase Substack import (~10 files)
      *.rb                          # ContentSync, ContentWatcher,
                                    # StaticGenerator, FeedGenerator,
                                    # ConfigGenerator, PageGenerator,
                                    # ImageVariantGenerator,
                                    # ResponsiveImageRenderer,
                                    # EmailRenderer, NewsletterRenderer,
                                    # PostmarkService, StripeProductManager,
                                    # ProductButtonRenderer, ProductCategory,
                                    # CollectionGridProcessor,
                                    # CollectionMembersFilter,
                                    # MediaDurationExtractor
    mailers/                        # ApplicationMailer, MemberMailer,
                                    # FallbackMailer, PasswordsMailer
    jobs/                           # Image variants, newsletter batches,
                                    # Substack import phases, Postmark
                                    # webhook processing, bulk uploads,
                                    # PerformUpdateJob
    javascript/controllers/         # Stimulus, importmap-pinned
    views/
      posts/                        # Public post layouts + types/
                                    # (article, audio, video, podcast)
      admin/, members/, products/, layouts/, shared/, ...
    helpers/

  config/
    routes.rb                       # Public + Admin + Members + Webhooks
    importmap.rb                    # JS pin definitions
    application.rb                  # Includes RoeSitePaths configuration

  lib/tasks/                        # content, images, static_site, media_reference

site/                             # Content root (file-backed, persistent)
  posts/                          # Markdown posts
  pages/                          # Markdown pages
  documentation/                  # Markdown docs
  products/                       # Store catalog (supports grouped variants: group, variant, primary fields)
  media/                          # Images, audio, video
  emails/                         # Email templates
  templates/                      # Reusable content blocks
  layout/                         # Layout config
  theme/                          # Theme files (CSS, fonts, images)
  system/                         # System-wide config
    global/                       # Global settings (deploy.yml, etc.)
    features/                     # Feature flags and configuration
    integrations/                 # Test API keys (Stripe, Postmark, Snipcart)
  db/                             # SQLite database files
  missing_media.yml               # Tracking for unresolved media refs

test/
  test_helper.rb                  # Minitest config, FactoryBot wiring
  test_helpers/                   # SessionTestHelper for auth in tests
  factories.rb                    # FactoryBot definitions (single file)
  controllers/, models/, services/, mailers/, helpers/, integration/
  fixtures/                       # YAML fixtures + fixtures/files/
```

## Major Subsystems

### Update & Deploy

Roe supports two workflows for updating production:

**1. In-App Update System (for production-only installations):**
- **VersionChecker**: Checks Codeberg repository (waotw/roe) for new releases with HTTPS → SSH fallback for private repos
- **BackupManager**: Creates DB and full site backups before updating
- **Downloader**: Clones new versions to `staging/`
- **MigrationTester**: Tests migrations on a copy before applying to production
- **SwitchManager**: Atomic directory swap (`current/` ↔ `staging/`)
- **UpdateOrchestrator**: Coordinates the entire flow with progress tracking

**Access**: Admin → Updates
**Process**: Check → Backup → Download → Test → Migrate → Switch → Restart

**2. Deploy to Live (for local development workflow):**
Deploy the current codebase from local to a live server via Kamal or Fly.io.
- **Access**: Admin → Updates & Deploy (or `./roe.sh deploy` from CLI)
- **Targets**: Kamal (SSH-based) or Fly.io (container platform)
- **VERSION file**: Must exist at `ROE_ROOT/VERSION` (git-tracked or manually created)
- **Fly.io Migrations**: Automatically run via `[deploy] release_command` in fly.toml
- **Docker Entrypoint**: Updated to detect Rails server and run `db:prepare` with proper path handling

**Rollback**: Automatic on update failure; manual rollback available for deploy

### Content sync
Markdown files in `site/` are the source of truth. `ContentSync` parses front-matter and body and upserts `Post`, `Page`, `Documentation`, `Medium`, `Product`, and `*Config` rows. `ContentWatcher` (dev) re-syncs on file changes. JSON metadata is stored as a text column and queried via SQLite `json_extract`.

### Integration Configuration (API Keys)
Payment and email integrations support dual-storage for test/live environments:
- **Test keys**: Stored in YAML files under `site/system/integrations/` (synced across environments)
- **Live keys**: Stored encrypted in the database (environment-specific)

**Access**: Admin → Settings → Integrations
**Services**: StripeConfig, PostmarkConfig, SnipcartConfig

This separation allows testing integrations in development with test keys while keeping live keys secure and environment-specific.

### Members + audiences
`Member` records back a magic-link / token-based auth flow under `app/controllers/members/`. The `HasAudience` concern controls who can see what (public / paid / draft). Paid access is gated by Stripe subscriptions managed via `StripeProductManager` and the `checkout_controller`.

### Store & Products
Products are Markdown files in `site/products/` with front-matter defining price, SKU, category, and status. Enable the store via `site/system/features/store.yml` (creates Snipcart integration).

**Product Grouping**: Products can be grouped as variants (e.g., one book with Paperback/Hardback/Ebook formats):
- Set `group: book-id` on all variants to link them
- Set `variant: "Paperback"` to label each format
- Set `primary: true` on the variant to show first in collections
- Collection grid shows variant list and price range with `groups: enabled`
- Button renderer auto-detects siblings and renders variant selector

**Configuration**:
- Store settings in `site/system/features/store.yml`: currency, default_domain, product_categories, grouped_products
- Product template for editor in store config
- SKU generation via `ProductCategory` service

### Podcast feeds
`PodcastConfig` (sourced from `site/system/features/podcast.yml`) supports multiple podcast series. `FeedGenerator` produces RSS/Atom for the main blog and per-podcast feeds, with `include_paid` / `show_paid_teasers` flags. Public feeds may show paid episodes as teasers (no enclosure); a separate `/podcast/:podcast_key/private.xml` route serves full audio to authenticated members via per-member tokens.

### Email
`MemberMailer` is implemented as plain class methods (not Rails ActionMailer subclassing). It checks for a connected `PostmarkConfig` and delivers via `PostmarkService`; otherwise it falls back to `FallbackMailer` (a regular `ApplicationMailer`) and `letter_opener` in development. Newsletter broadcasts are batched via `QueueNewsletterBatchesJob` + `SendNewsletterJob` with delivery tracked in `NewsletterSend`. Postmark webhooks land in `webhooks/postmark_controller` and are processed asynchronously.

### Substack import
`Admin::ImportsController` drives a three-phase import (`ImportPostsJob`, `ImportMembersJob`, `ImportDeliveriesJob`). Logic lives in `app/services/substack_importer/` (converter, frontmatter, html_loader, csv_parser, media_handler, live_fetcher, etc.). Audience mapping (free/paid) and media migration are handled per-post.

### Static site generation
`StaticGenerator` builds a static HTML mirror of the public site using a manifest for incremental rebuilds. It coordinates with `ImageVariantGenerator` / `ResponsiveImageRenderer` for responsive image output. Outputs to `static_site/` at root level (outside versioned directory). Triggered via `bin/rails static_site:build` or the admin static-site controller.

## Testing Conventions

- Framework: **Minitest** (Rails default), NOT RSpec
- Fixtures AND FactoryBot both available; factories defined in `test/factories.rb` (single file)
- `include FactoryBot::Syntax::Methods` is enabled globally; use `create(:post)`, `build(:user)`, etc.
- Integration tests inherit `ActionDispatch::IntegrationTest`
- Model tests inherit `ActiveSupport::TestCase`
- Auth helper: `sign_in_as(user)` / `sign_out` (from `SessionTestHelper`)
- Parallel execution is **disabled** (`parallelize(workers: 0)` in `test/test_helper.rb`) — content-sync tests touch shared DB state
- Global `setup` in `ActiveSupport::TestCase` clears `Post`, `Page`, `Documentation`, `Medium`, `SiteConfig`
- Concerns are tested under `test/models/concerns/`

## Code Style

Follow **rubocop-rails-omakase** (configured in `.rubocop.yml`). Key rules:

### Formatting
- 2-space indentation, no tabs
- Frozen string literal not required (omakase style)
- Trailing commas in multi-line arrays/hashes
- Spaces inside brackets in omakase style: `[ a, b ]`, `{ a: 1 }`

### Naming
- Classes/Modules: `PascalCase` (e.g., `ContentSync`, `HasMetadata`, `PodcastConfig`)
- Methods/variables: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`
- DB columns: `snake_case`, `_id` for FKs, `_at` for timestamps

### Imports / Requires
- Use `require_relative` for local files within the same directory tree
- Use `require` for gems
- App code is autoloaded via Zeitwerk; services/jobs/mailers are picked up automatically

### Models
- Shared behavior lives in `app/models/concerns/` (`ActiveSupport::Concern`)
- Query objects / scopes go directly in models
- JSON metadata stored as a text column, queried with SQLite `json_extract`
- File-backed models (Post, Page, Documentation, Medium, Product) round-trip from `site/` via `ContentSync`
- **Path handling**: Use `RoeSitePaths::SITE_PATH` for site content, `RoeSitePaths::ROE_ROOT` for root-level access

### Controllers
- Admin controllers inherit `Admin::BaseController`
- Member-facing controllers inherit `Members::BaseController`
- Public controllers inherit `ApplicationController`
- Use `before_action` for shared setup
- Raise `ActiveRecord::RecordNotFound` for 404s (handled by `render_not_found` in `ApplicationController`)
- Paid-content gating goes through `SiteController#check_paid_access!`
- Admin layout uses `content_for :admin_nav` flag system:
  - `admin.html.erb` wrapper sets the flag
  - `application.html.erb` conditionally renders navigation
  - Sign-in page shows logo only; authenticated pages show full nav
  - Edit pages (pages, posts, products, emails) use dynamic layout: `layout -> { action_name == "edit" ? "editor" : "admin" }`

### Services
- Plain Ruby classes in `app/services/`
- Class-method convenience wrappers (e.g., `def self.sync_all; new.sync_all; end`)
- No base class; self-contained
- Multi-file service modules live in their own subdirectory (see `substack_importer/`, `roe_updater/`)

### Mailers
- `MemberMailer` is non-standard: class methods that route through `PostmarkService` (preferred) or `FallbackMailer` (when Postmark is unconfigured)
- Traditional ActionMailers (`PasswordsMailer`, `FallbackMailer`) inherit `ApplicationMailer`

### Jobs
- ActiveJob with `solid_queue` adapter
- Long-running operations (image variants, newsletter sends, Substack imports, Postmark webhooks, updates) run as jobs

### Views
- Layout inheritance uses `content_for` flags for conditional rendering
- `admin.html.erb` - Wrapper that sets `content_for :admin_nav, true`
- `application.html.erb` - Base layout with conditional navigation
- `editor.html.erb` - Full-screen layout for editing (no navigation)
- Video player uses YouTube-style controls with fullscreen support

### Error Handling
- Rescue broad `=> e` in service methods, log with `Rails.logger.error`
- Controller-level: `rescue_from ActiveRecord::RecordNotFound`
- Return `nil` on failure, objects on success, `:warning` symbol for partial success

### JavaScript
- Importmap (no Node/Webpack)
- Stimulus controllers in `app/javascript/controllers/`
- Pins defined in `config/importmap.rb`
- Notable controllers: `audio_player`, `editor`, `metadata_editor`, `media_picker`, `media_bulk_select`, `css_editor`, `footnote_tooltip`

### CSS
- Tailwind CSS (via `tailwindcss-rails`) for the application UI
- Public site uses a theme system with dynamic CSS generation served from `/theme/:filename.css`
- **Naming Convention**: All CSS classes use semantic naming (not BEM):
  - Collections: `.collection-item`, `.item-body`, `.item-image`, `.item-title`
  - Media Players: `.player`, `.player-header`, `.player-controls`, `.video-controls`
  - Post Headers: `.post-header-top`, `.feed-link`, `.header-image`
- System fonts and images are served from `/system/...`

## Site Path Configuration

Roe uses centralized path configuration via `RoeSitePaths` module (defined in `config/application.rb`):

```ruby
RoeSitePaths::ROE_ROOT      # Root directory (/roe/ or /roe/current/../)
RoeSitePaths::SITE_PATH     # Site content directory
RoeSitePaths::STATIC_SITE_PATH  # Static output directory
```

**Important**: When referencing site paths in code, always use `RoeSitePaths::SITE_PATH` instead of `Rails.root.join('site')` to support both standard and versioned directory structures.

**Example**:
```ruby
# Good
File.join(RoeSitePaths::SITE_PATH, 'posts', filename)

# Bad (won't work in versioned structure)
Rails.root.join('site', 'posts', filename)
```

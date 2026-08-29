# AGENTS.md

## Overview

Roe is a Rails 8.1 file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store. Content (posts, pages, documentation, products) is authored as Markdown files in `site/` and synced to SQLite via `ContentSync`. The app can also generate a fully static version of the public site. Ruby 4.0.5.

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
                                    # MediaDurationExtractor,
                                    # MediaUsageIndex (media backlinks),
                                    # MediaReferenceRewriter (rename fixups),
                                    # SearchIndexGenerator (client-side search
                                    # index), PostLinkPreview (live card fields)
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

Two distinct workflows that target different audiences.

**1. In-App Update System (DEVELOPMENT installs only)**

Updates the developer's local Roe install to a new tagged release from Codeberg. Hidden in production: `Admin::UpdatesController#block_in_production` redirects every action and the nav link is conditionally rendered. Migrations always target the development SQLite — production DBs are migrated by the deploy flow (Kamal/Fly release_command), not by this system. `RAILS_ENV` is hardcoded to `development` for the migration subprocess to close the footgun where booting dev with `RAILS_ENV=production` would otherwise route migrations at the wrong DB.

Orchestrated by `RoeUpdater::UpdateOrchestrator`, run inside `PerformUpdateJob`. Components:

- **VersionChecker**: Reads root `/VERSION` for the installed version; queries Codeberg (HTTPS → SSH fallback) for the latest tag. Tags must carry the `v` prefix (`v0.1.0`); bare-numbered tags are ignored. Suffixed tags (`-nightly.N`, `-rc.N`) are pre-releases — shown only to dev installs / the `nightly` channel, and ordered via `Gem::Version`. Tag & release scheme: `docs/21-development-workflow.md`.
- **BackupManager**: Snapshots dev + prod SQLite to `site_backups/` with a timestamp stamped onto the `UpdateStatus` so rollback restores the right one.
- **Downloader**: `git clone --branch <tag>` into `staging/`.
- **MigrationTester**: Rsyncs migrations from `staging/` into a throwaway copy of `current/` and dry-runs them against a cloned dev DB.
- **SwitchManager**: Renames `current/` → `current.backup/`, `staging/` → `current/`. Rollback uses a rename-to-quarantine pattern (`current/` → `current.broken-<ts>`) so the swap is atomic and immune to asset-writer races.
- **UpdateOrchestrator**: Coordinates the 11-step pipeline + progress tracking via `UpdateStatus`.

Step pipeline (matches `UpdateOrchestrator::STEPS`):

1. `validating` — git available, `staging/` empty
2. `backing_up_db` — DB snapshots
3. `downloading` — clone tag to `staging/`
4. `testing` — dry-run migrations against a copy
5. `migrating` — apply migrations to the real dev DB
6. `switching` — rename current → current.backup, staging → current
7. `preserving_secrets` — copy `config/master.key` + `tmp/development_secret.txt` from `current.backup/` (gitignored, absent from the clone — without this the user gets signed out)
8. `syncing_root_files` — copy `roe.sh`, `README.md`, `LICENSE` (`UpdateOrchestrator::ROOT_SYNC_FILES`) from `current/` to root. `AGENTS.md` is intentionally not synced — it's dev material that stays in `current/`. `bin/sync-from-site` mirrors the same set for release prep.
9. `writing_version` — rewrite both root `/VERSION` and `current/VERSION` with the new tag's full YAML
10. `building_assets` — `assets:precompile` against the new code
11. `restarting` — schedule a 5-second exit so the supervisor (`roe.sh`) relaunches Puma on the new code

**Rollback (automatic on any step failure)**: `handle_failure` restores the DB from this update's backup, calls `SwitchManager.rollback` (quarantine + restore), re-mirrors `current/VERSION` to root `/VERSION` so the admin UI reflects the rolled-back state, and wipes `staging/`. Failures inside rollback propagate to the user with the real exception class + message — there is intentionally no silent swallow.

**Restart-aware UI**: The Updates index decides "Restart Roe" vs "Update Successful" by comparing `@status.completed_at` against `Rails.application.config.server_boot_time` (captured at initializer load). `completed_at > server_boot_time` means the user still needs to restart manually.

**Access**: Admin → Updates

**2. Deploy to Live (production deployment)**

Deploys the current codebase from local to a live server via Kamal or Fly.io.

- **Access**: Admin → Updates & Deploy (or `./roe.sh deploy` from CLI)
- **Targets**: Kamal (SSH-based) or Fly.io (container platform)
- **VERSION file**: Lives at `ROE_ROOT/VERSION`. The in-app updater keeps this in sync with `current/VERSION` automatically; manual creation only needed for fresh installs.
- **Fly.io migrations**: Run via `[deploy] release_command` in `fly.toml`
- **Docker entrypoint**: Detects Rails server and runs `db:prepare` with proper path handling
- **Rollback**: Manual (via the deploy target's own tooling)

### Content sync
Markdown files in `site/` are the source of truth. `ContentSync` parses front-matter and body and upserts `Post`, `Page`, `Documentation`, `Medium`, `Product`, and `*Config` rows. `ContentWatcher` (dev) re-syncs on file changes. JSON metadata is stored as a text column and queried via SQLite `json_extract`.

### Site configuration & settings
Global config files live in `site/system/global/`; each has a dedicated `SiteConfig` accessor that reads its file directly (no cross-file lookup):
- `SiteConfig.get(k)` → `site.yml` (identity, branding, theme, sync, updates, SSG)
- `SiteConfig.content(k)` → `content.yml` (content rendering + search; **nested** keys, e.g. `content("search.all_pages")`, `content("heading_links")`)
- `.fonts` / `.custom_code` / `.development` → their files; `.feature(type, k)` / `.default(type, k)` → `features/*.yml` / `defaults/*.yml`

**Moving keys between config files**: `ConfigGenerator#migrate_content_config!` is the pattern — an idempotent boot migration (runs inside `generate_all`) that relocates keys while preserving user values, paired with a legacy fallback in the accessor so un-migrated installs keep reading the old location. Safe to run on every boot.

**Admin settings are schema-driven**: `Admin::ConfigsController` defines `SITE_CONFIG_SCHEMA` / `CONTENT_CONFIG_SCHEMA` (sections → fields with type/label/hint). The shared `shared/_config_editor` partial has a **hardcoded section block per `config_type`**; on save it serializes `[data-config-field]` inputs into the YAML `content` param, splitting field names on `.` so dotted keys (`search.all_pages`, `theme.active`) nest. Config YAML carries **no comments** — put help text in the schema `hint:`, not the file.

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

### Content builders & search
**Editor block builders**: Toolbar modals turn form fields into fenced blocks — `collection_builder`, `card_builder`, `gallery_builder` (Stimulus). Options come from `CollectionBuilderSchema` / `CardBuilderSchema` (single source of truth: labels, types, hints, `depends_on` field visibility). Card builders show live inherited placeholders via `PostLinkPreview`, which derives a referenced item's fields (post-link / product-link card types, rendered by `HasMarkdownExtensions`).

**Public search**: `SearchIndexGenerator` builds a JSON index served at `/search-index.json` (`SearchController`) and baked into static builds, so search works with no backend. The `site_search` (overlay) and `search_trigger` (content-embedded) Stimulus controllers filter it client-side, scoped by source / post_type / tags.

### The editor
`editor_controller` + `shared/_editor` power the admin editor for posts/pages/products/emails. A few non-obvious pieces:

- **Standalone document / unsaved-changes guard**: `layouts/editor.html.erb` sets `turbo-visit-control: reload` so the editor is a full document, not a Turbo snapshot — leaving via Back/Forward/close/reload is a real unload and the `beforeunload` dirty guard fires. **Don't remove that meta tag.** In-app link clicks are caught via `turbo:before-visit` and confirmed with `shared/_leave_modal`.
- **Live preview**: the editor POSTs the current (unsaved) content to the type's `preview` action and pushes the rendered `<main>` to the open preview tab over a `BroadcastChannel("preview-<type>-<id>")`; the preview page's `preview_receiver` controller swaps it in place (scroll preserved).
- **Shared action bar**: Save/Preview/(Un)publish + the save-state dot live in `shared/_editor_primary_actions` (rendered in-flow *and* inside the sticky `editor_drawer`); the full header lives in `shared/_editor_actions`, driven by `resource` + `resource_type`. Edit the shared partials, not per-type copies.
- **Publish modal = metadata editor is the source of truth**: `admin/posts/_publish_modal` (shared) reflects the editor — present required fields are read-only "✓" bullets, missing ones are inputs that write straight into the editor via `editor#syncModalField` → `applyMetadataField`. The SKU generator writes to the editor and fires `publish-modal:refresh` to rebuild; `completePublish` submits the editor form.

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
- **`file_path` storage is inconsistent** (known issue, slated to unify on relative): `Post`/`Page`/`Documentation` store an **absolute** realpath; `Product` stores a path **relative** to `SITE_PATH`. Never assume `record.file_path` is absolute — resolve it (prepend `SITE_PATH` when it doesn't start with `/`) before any `File.read`/`File.file?`. This gap silently skipped products in `MediaReferenceRewriter` until fixed.

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
- Notable controllers: `audio_player`, `editor`, `editor_drawer` (sticky action bar), `preview_receiver` (in-place preview swap, runs in the preview tab), `metadata_editor`, `media_picker`, `media_bulk_select`, `media_filter` (media browse tabs/search), `image_upload` (config image field verify/preview), `config_focus` (focuses a config field from `?focus=`), `css_editor`, `footnote_tooltip`, `site_search`, `search_trigger`, `collection_builder`, `card_builder`, `gallery_builder`

### CSS
- Tailwind CSS (via `tailwindcss-rails`) for the application UI
  - The dev watcher runs `tailwindcss:watch[always]` (in `roe.sh` and `Procfile.dev`). The `[always]` is **required**: plain `tailwindcss:watch` binds to a TTY and exits immediately when backgrounded, silently stopping all CSS rebuilds. If new utility classes aren't taking effect, check the watcher is alive (`pgrep -fl tailwindcss:watch`) before anything else.
- Public site uses a theme system with dynamic CSS generation served from `/theme/:filename.css`
- **Naming Convention**: All CSS classes use semantic naming (not BEM):
  - Collections: `.collection-item`, `.item-body`, `.item-image`, `.item-title`
  - Media Players: `.player`, `.player-header`, `.player-controls`, `.video-controls`
  - Post Headers: `.post-header-top`, `.feed-link`, `.header-image`
- System fonts and images are served from `/system/...`
- **Config image fields** (logo, favicon, social image, podcast artwork) accept either a bare filename (resolved to `/system/images/<name>`, i.e. `site/system/assets/images/`) or an absolute `/media/...` path uploaded via the main Media browser. Resolve config image values through the `config_image_path` helper so both forms work

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

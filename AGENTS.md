# AGENTS.md

## Overview

Roe is a Rails 8.1 file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store. Content (posts, pages, documentation, products) is authored as Markdown files in `site/` and synced to SQLite via `ContentSync`. The app can also generate a fully static version of the public site. Ruby 3.2.2.

Primary integrations: **Stripe** (payments / paid memberships), **Postmark** (transactional + broadcast email, with a fallback to ActionMailer when unconfigured), and a multi-phase **Substack importer**.

## Build / Run / Test Commands

```bash
# Setup
bin/setup                         # Install deps, prepare DB, sync content

# Run dev server
bin/dev                           # Starts Puma + Tailwind watcher (Procfile.dev)

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/post_test.rb

# Run a single test by name
bin/rails test -n test_should_get_index

# Run a single test by line number
bin/rails test test/controllers/posts_controller_test.rb:4

# Lint
bin/rubocop                       # RuboCop (rubocop-rails-omakase style)
bin/rubocop -A                    # Auto-correct

# Security
bin/brakeman                      # Static security analysis
bin/bundler-audit                 # Check gems for known vulnerabilities

# Database
bin/rails db:migrate
bin/rails db:seed

# Content / site tasks
bin/rails content:sync            # Sync site/ files into DB
bin/rails content:watch           # Watch site/ for changes (dev)
bin/rails images:generate_variants
bin/rails static_site:build       # Generate static HTML for public site
bin/rails media_reference:rebuild # Rebuild MediaReference join table
```

## Project Structure

```
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
                                  # SnipcartConfig, Import, NewsletterSend,
                                  # MediaReference, Current
  services/
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
                                  # webhook processing, bulk uploads
  javascript/controllers/         # Stimulus, importmap-pinned
  views/
    posts/                        # Public post layouts + types/
                                  # (article, audio, video, podcast)
    admin/, members/, products/, layouts/, shared/, ...
  helpers/

config/
  routes.rb                       # Public + Admin + Members + Webhooks
  importmap.rb                    # JS pin definitions

lib/tasks/                        # content, images, static_site, media_reference

site/                             # Content root (file-backed)
  posts/                          # Markdown posts
  pages/                          # Markdown pages
  documentation/                  # Markdown docs
  products/                       # Store catalog
  media/                          # Images, audio, video
  emails/                         # Email templates
  templates/                      # Reusable content blocks
  layout/                         # Layout config
  theme/                          # Theme files (CSS, fonts, images)
  system/                         # System-wide config
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

### Content sync
Markdown files in `site/` are the source of truth. `ContentSync` parses front-matter and body and upserts `Post`, `Page`, `Documentation`, `Medium`, `Product`, and `*Config` rows. `ContentWatcher` (dev) re-syncs on file changes. JSON metadata is stored as a text column and queried via SQLite `json_extract`.

### Members + audiences
`Member` records back a magic-link / token-based auth flow under `app/controllers/members/`. The `HasAudience` concern controls who can see what (public / paid / draft). Paid access is gated by Stripe subscriptions managed via `StripeProductManager` and the `checkout_controller`.

### Podcast feeds
`PodcastConfig` (sourced from `site/system/features/podcast.yml`) supports multiple podcast series. `FeedGenerator` produces RSS/Atom for the main blog and per-podcast feeds, with `include_paid` / `show_paid_teasers` flags. Public feeds may show paid episodes as teasers (no enclosure); a separate `/podcast/:podcast_key/private.xml` route serves full audio to authenticated members via per-member tokens.

### Email
`MemberMailer` is implemented as plain class methods (not Rails ActionMailer subclassing). It checks for a connected `PostmarkConfig` and delivers via `PostmarkService`; otherwise it falls back to `FallbackMailer` (a regular `ApplicationMailer`) and `letter_opener` in development. Newsletter broadcasts are batched via `QueueNewsletterBatchesJob` + `SendNewsletterJob` with delivery tracked in `NewsletterSend`. Postmark webhooks land in `webhooks/postmark_controller` and are processed asynchronously.

### Substack import
`Admin::ImportsController` drives a three-phase import (`ImportPostsJob`, `ImportMembersJob`, `ImportDeliveriesJob`). Logic lives in `app/services/substack_importer/` (converter, frontmatter, html_loader, csv_parser, media_handler, live_fetcher, etc.). Audience mapping (free/paid) and media migration are handled per-post.

### Static site generation
`StaticGenerator` builds a static HTML mirror of the public site using a manifest for incremental rebuilds. It coordinates with `ImageVariantGenerator` / `ResponsiveImageRenderer` for responsive image output. Triggered via `bin/rails static_site:build` or the admin static-site controller.

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

### Controllers
- Admin controllers inherit `Admin::BaseController`
- Member-facing controllers inherit `Members::BaseController`
- Public controllers inherit `ApplicationController`
- Use `before_action` for shared setup
- Raise `ActiveRecord::RecordNotFound` for 404s (handled by `render_not_found` in `ApplicationController`)
- Paid-content gating goes through `SiteController#check_paid_access!`

### Services
- Plain Ruby classes in `app/services/`
- Class-method convenience wrappers (e.g., `def self.sync_all; new.sync_all; end`)
- No base class; self-contained
- Multi-file service modules live in their own subdirectory (see `substack_importer/`)

### Mailers
- `MemberMailer` is non-standard: class methods that route through `PostmarkService` (preferred) or `FallbackMailer` (when Postmark is unconfigured)
- Traditional ActionMailers (`PasswordsMailer`, `FallbackMailer`) inherit `ApplicationMailer`

### Jobs
- ActiveJob with `solid_queue` adapter
- Long-running operations (image variants, newsletter sends, Substack imports, Postmark webhooks) run as jobs

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
- System fonts and images are served from `/system/...`

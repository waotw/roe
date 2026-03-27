# AGENTS.md

## Overview

Roe is a Rails 8.1 file-backed CMS/blog. Content (posts, pages, documentation) is stored as Markdown files in `site/` and synced to SQLite via `ContentSync`. Ruby 3.2.2.

## Build / Run / Test Commands

```bash
# Setup
bin/setup                  # Install deps, prepare DB, sync content

# Run dev server
bin/dev                    # Starts Puma + Tailwind watcher (Procfile.dev)

# Run all tests
bin/rails test

# Run a single test file
bin/rails test test/models/post_test.rb

# Run a single test by name
bin/rails test -n test_should_get_index

# Run a single test by line number
bin/rails test test/controllers/posts_controller_test.rb:4

# Lint
bin/rubocop                # RuboCop (rubocop-rails-omakase style)
bin/rubocop -A             # Auto-correct

# Security
bin/brakeman               # Static security analysis
bin/bundler-audit          # Check gems for known vulnerabilities

# Database
bin/rails db:migrate
bin/rails db:seed

# Sync content from site/ files into DB
bin/rails content:sync
```

## Project Structure

```
app/
  controllers/             # Public + Admin:: namespaced controllers
  models/                  # ApplicationRecord subclasses + concerns/
  models/concerns/         # HasMetadata, HasMarkdownExtensions, HasInlineFootnotes
  services/                # ContentSync, StaticGenerator, FeedGenerator, etc.
  views/                   # ERB templates
  javascript/              # Stimulus controllers, importmap-pinned
test/
  test_helper.rb           # Minitest config, parallel workers, FactoryBot
  test_helpers/            # SessionTestHelper for auth in tests
  factories.rb             # FactoryBot definitions (single file)
  controllers/             # ActionDispatch::IntegrationTest
  models/                  # ActiveSupport::TestCase
  services/                # Service-level tests
site/                      # Content root: posts/, pages/, documentation/, media/, system/
```

## Testing Conventions

- Framework: **Minitest** (Rails default), NOT RSpec
- Fixtures AND FactoryBot both available; factories defined in `test/factories.rb`
- Include FactoryBot syntax: `include FactoryBot::Syntax::Methods`
- Use `create(:post)`, `build(:user)` etc. for test data
- Integration tests inherit `ActionDispatch::IntegrationTest`
- Model tests inherit `ActiveSupport::TestCase`
- Auth helper: `sign_in_as(user)` / `sign_out` (from `SessionTestHelper`)
- Tests run in parallel: `parallelize(workers: 0)` in test_helper.rb
- `setup` method in `ActiveSupport::TestCase` clears Post, Page, Documentation, Medium, SiteConfig

## Code Style

Follow **rubocop-rails-omakase** (configured in `.rubocop.yml`). Key rules:

### Formatting
- 2-space indentation, no tabs
- Frozen string literal not required (omakase style)
- Trailing commas in multi-line arrays/hashes
- Spaces inside brackets: `[a, b]` not `[ a, b ]`

### Naming
- Classes/Modules: `PascalCase` (e.g., `ContentSync`, `HasMetadata`)
- Methods/variables: `snake_case` (e.g., `sync_posts`, `file_path`)
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `DEFAULTS_PATH`)
- Database columns: `snake_case` with `_id` for foreign keys, `_at` for timestamps

### Imports / Requires
- Use `require_relative` for local files within same directory tree
- Use `require` for gems
- Services are autoloaded via `config.autoload_lib`

### Models
- Use concerns (`ActiveSupport::Concern`) for shared behavior in `app/models/concerns/`
- Query objects / scopes go directly in models
- JSON metadata stored as text column, queried via SQLite `json_extract`

### Controllers
- Admin controllers inherit from `Admin::BaseController`
- Public controllers inherit from `ApplicationController`
- Use `before_action` for shared setup, `rescue_from` for error handling
- Use `raise ActiveRecord::RecordNotFound` for 404s (handled by `render_not_found` in ApplicationController)

### Services
- Plain Ruby classes in `app/services/`
- Class method convenience wrappers: `def self.sync_all; new.sync_all; end`
- No base class; self-contained

### Error Handling
- Rescue broad `=> e` in service methods, log with `Rails.logger.error`
- Controller-level: `rescue_from ActiveRecord::RecordNotFound`
- Return `nil` on failure, objects on success, `:warning` symbol for partial success

### JavaScript
- Importmap (no Node/Webpack)
- Stimulus controllers in `app/javascript/controllers/`
- Pins defined in `config/importmap.rb`

### CSS
- Tailwind CSS via `tailwindcss-rails` for application
- Theme system with dynamic CSS generation for public site

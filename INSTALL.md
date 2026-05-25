# Roe Installation Guide

## Directory Structure

When you download Roe, you get a root folder (e.g. `/roe`) containing:

```
your-roe-folder/         # Root — name this whatever you like
  current/               # The Rails application (versioned)
  site/                  # Your content — posts, pages, media, config
  roe.sh                 # Server management script (see below)
  start.command          # macOS: double-click to start the server
```

`current/` and `site/` each have their own git repositories. The root
folder is not tracked by git — rename it to anything you like.

---

## Quick Start

### Option A: Double-click (macOS)

Double-click `start.command` in the root folder. If this is your first
time, it will run the requirements check and setup automatically, then
start the server and open your browser.

### Option B: Terminal

```bash
cd your-roe-folder
./roe.sh check     # First time: checks requirements and guides setup
./roe.sh start     # Start the server (after setup is complete)
```

Then visit **http://localhost:3000**

---

## `roe.sh` — Server Management Script

All server management is done from the **root folder** via `roe.sh`.
You never need to `cd` into `current/` for day-to-day use.

### Commands

```bash
./roe.sh check      # Check system requirements and guide installation
./roe.sh setup      # Run full setup (deps, database, config, admin user)
./roe.sh start      # Start the development server
./roe.sh stop       # Stop the server (Rails + Tailwind watcher)
./roe.sh restart    # Restart the server
./roe.sh status     # Show server status and requirements summary
./roe.sh console    # Open Rails console
./roe.sh update     # Check for Roe updates
```

### What `roe.sh start` does

- Starts the Rails server on `http://localhost:3000`
- Starts the Tailwind CSS watcher (dev only — recompiles CSS on changes)
- Runs Solid Queue inside Puma for background job processing
- Prompts to open the browser automatically
- Manages PID files for clean stop/restart

To use a different port:
```bash
PORT=4000 ./roe.sh start
```

### What `roe.sh check` does

Interactively checks for all required dependencies and guides you through
installing anything missing:

1. Ruby 3.2.2+ (via rbenv or rvm)
2. Git
3. Bundler
4. SQLite3
5. libvips (optional, for image processing)

After passing all checks, offers to run setup automatically.

### What `roe.sh setup` does

Runs `current/bin/setup` which:

1. Installs Ruby gems (`bundle install`)
2. Generates `config/master.key` if missing
3. Generates Active Record Encryption keys in credentials
4. Creates the `site/` directory structure if missing
5. Creates and migrates all databases (main, cache, queue, cable)
6. Generates default config files (`site.yml`, `fonts.yml`, etc.)
7. Copies the default theme to `site/theme/`
8. Generates default pages (`home.md`)
9. Syncs content to the database
10. Creates an admin user (interactive)
11. Creates `start.command` if missing
12. Starts the server automatically

---

## Prerequisites

### Required

#### Ruby 3.2.2+

Roe requires Ruby 3.2.2 or later (specified in `current/.ruby-version`).
`roe.sh` automatically activates the correct version via rbenv or rvm
when run from the root folder.

**Install via rbenv (recommended):**
```bash
brew install rbenv
eval "$(rbenv init -)"   # Add to ~/.zshrc or ~/.bash_profile
rbenv install 3.2.2
rbenv global 3.2.2
```

**Install via asdf:**
```bash
brew install asdf
asdf plugin add ruby
asdf install ruby 3.2.2
asdf global ruby 3.2.2
```

**Verify:**
```bash
ruby --version  # Should show 3.2.2 or later
```

#### Git

Required for cloning and the version checker.

```bash
git --version       # Usually pre-installed on macOS
xcode-select --install  # If not installed
```

#### SQLite3

Usually pre-installed on macOS. Verify:
```bash
sqlite3 --version
# If missing:
brew install sqlite3
```

#### Bundler

Comes with Ruby. If missing:
```bash
gem install bundler
```

### Optional but Recommended

#### libvips (Image Processing)

Required for image variant generation (thumbnails, responsive images).
Without it, image processing falls back to slower methods or skips variants.

```bash
brew install libvips
```

---

## Post-Setup Configuration

### 1. Configure your site

Edit `site/system/global/site.yml` — or use **Admin → Settings → site.yml**:

```yaml
title: "My Site"
url: "https://mysite.com"
author: "Your Name"
author_email: "you@example.com"
```

### 2. Configure integrations (optional)

Integrations are managed in **Admin → Settings → Integrations**.

Test keys are saved to YAML files in `site/system/integrations/` and
work in all environments. Live keys are stored encrypted in the database
and are only saved in production.

| Integration | Feature | Test config file |
|---|---|---|
| Stripe | Payments | `site/system/integrations/payments.yml` |
| Postmark | Newsletters/email | `site/system/integrations/newsletters.yml` |
| Snipcart | Store | `site/system/integrations/snipcart.yml` |

### 3. Customize your theme

Edit `site/theme/default.css` or create a new theme file and activate
it in **Admin → Settings → site.yml → Theme**.

---

## For Developers

If you're working on the Roe application itself, you can work directly
in `current/` using standard Rails commands:

```bash
cd current

bin/dev              # Start server + Tailwind watcher via foreman
bin/rails console    # Rails console
bin/rails test       # Run test suite
bin/rubocop          # Lint
```

Note: `bin/dev` requires `foreman` to be installed:
```bash
gem install foreman
```

---

## Troubleshooting

### "Ruby version mismatch"
Ensure rbenv/rvm is initialised in your shell and the correct version
is installed. `roe.sh` reads `current/.ruby-version` and activates it
automatically.

### "bundle install fails"
```bash
cd current
gem install bundler
bundle install
```

### "master.key missing"
`roe.sh setup` generates this automatically. To regenerate manually:
```bash
cd current
ruby -e "require 'securerandom'; File.write('config/master.key', SecureRandom.hex(16))"
```

### "AR Encryption keys missing"
Run setup again — it detects and generates these automatically:
```bash
./roe.sh setup
```

### Images not generating variants
Install libvips:
```bash
brew install libvips
```

### Server won't stop
```bash
./roe.sh stop       # Stops Rails server + Tailwind watcher
./roe.sh status     # Check what's running
```

---

## Development vs Production

| | Development | Production |
|---|---|---|
| API keys | Test keys in `site/system/integrations/*.yml` | Live keys encrypted in database |
| Email | Letter opener (preview in browser) | Postmark |
| Database | SQLite in `site/db/development/` | SQLite in `site/db/` |
| Assets | Tailwind watcher rebuilds on change | Pre-compiled at deploy |
| Content | Edit files in `site/` directly | Sync from dev via Site Sync |

---

## Deployment

Roe supports two deployment targets:

- **Kamal** — self-hosted on any VPS (DigitalOcean, Hetzner, etc.)
- **Fly.io** — managed cloud deployment

Configure in **Admin → Settings → deploy.yml**, then deploy from
**Admin → Updates & Deploy**.

See `docs/` for detailed deployment guides.

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| macOS | 10.15 (Catalina) | 13+ (Ventura) |
| Linux | Ubuntu 20.04 | Ubuntu 22.04+ |
| RAM | 2GB | 4GB+ |
| Disk | 1GB | 5GB+ (for media) |

---

## Getting Help

- **Documentation:** `current/docs/` and `current/AGENTS.md`
- **Issues:** https://codeberg.org/waotw/roe/issues

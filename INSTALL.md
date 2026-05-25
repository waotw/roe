# Roe Installation Guide

## Quick Start

```bash
# Clone the repository
git clone git@codeberg.org:waotw/roe.git
cd roe

# Run setup (installs dependencies, creates database, starts server)
./bin/setup
```

Then visit http://localhost:3000

---

## Prerequisites

### Required

#### 1. **Ruby 3.2.2**

Roe requires Ruby 3.2.2 exactly (specified in `.ruby-version`).

**Option A: Using rbenv (recommended)**
```bash
# Install rbenv
brew install rbenv

# Add to your shell (~/.zshrc or ~/.bash_profile)
eval "$(rbenv init -)"

# Restart terminal, then install Ruby
rbenv install 3.2.2
rbenv global 3.2.2
```

**Option B: Using asdf**
```bash
# Install asdf and Ruby plugin
brew install asdf
asdf plugin add ruby
asdf install ruby 3.2.2
asdf global ruby 3.2.2
```

**Verify:**
```bash
ruby --version  # Should show 3.2.2
```

#### 2. **Git**

Required for cloning and the version checker.

```bash
# macOS (usually pre-installed)
git --version

# If not installed:
xcode-select --install
```

#### 3. **Bundler**

Comes with Ruby, but verify:
```bash
gem install bundler
```

---

### Optional but Recommended

#### 4. **libvips** (Image Processing)

Needed for image variant generation (thumbnails, responsive images).

```bash
brew install libvips
```

Without this, image processing will fall back to slower methods or skip variants.

#### 5. **SQLite3**

Usually pre-installed on macOS. Verify:
```bash
sqlite3 --version
```

If missing:
```bash
brew install sqlite3
```

---

## Detailed Installation

### Step 1: Get Roe

```bash
# Clone from Codeberg
git clone git@codeberg.org:waotw/roe.git

# Or download ZIP from:
# https://codeberg.org/waotw/roe/archive/main.zip
```

### Step 2: Run Setup

```bash
cd roe
./bin/setup
```

This script will:
- Install Ruby gems
- Generate master.key for encryption
- Create Active Record encryption keys
- Set up the site directory structure
- Create and migrate the database
- Generate default configuration files
- Copy default theme
- Create an admin user
- Start the development server

### Step 3: Access the Site

- **Public site:** http://localhost:3000
- **Admin panel:** http://localhost:3000/admin
- **Login credentials:** Displayed at end of setup

---

## Post-Setup Configuration

### 1. Configure Integrations (Optional)

**Test Environment** (development):
```bash
# Edit test API keys
vim site/system/integrations/stripe.yml
vim site/system/integrations/postmark.yml
vim site/system/integrations/snipcart.yml
```

**Production**:
- Go to Admin → Settings → Integrations
- Enter live API keys (stored encrypted in database)

### 2. Configure Site Settings

```bash
vim site/system/global/site.yml
```

Set your site name, description, author info, etc.

### 3. Customize Theme

Edit `site/theme/default.css` or create new theme files.

---

## Troubleshooting

### "Ruby version mismatch"
Install Ruby 3.2.2 using rbenv/asdf (see Prerequisites)

### "bundle install fails"
Ensure you have the correct Ruby version and bundler:
```bash
gem install bundler
bundle install
```

### "master.key missing"
The setup script generates this automatically. If you need to regenerate:
```bash
rm config/master.key
bin/rails credentials:edit
```

### "Permission denied (SSH)" when checking updates
Version checker needs SSH access to Codeberg. Ensure your SSH key is added:
```bash
ssh-add ~/.ssh/id_ed25519  # or your key
```

### Images not generating variants
Install libvips:
```bash
brew install libvips
```

---

## Development vs Production

### Development
- Test API keys in `site/system/integrations/*.yml`
- SQLite database
- Letter opener for email preview
- File-based content in `site/`

### Production
- Live API keys in encrypted database
- Can use SQLite or PostgreSQL
- Postmark for email (or configure SMTP)
- Same file-based content structure

---

## Next Steps

1. **Create your first post:**
   ```bash
   vim site/posts/hello-world.md
   ```

2. **Customize your homepage:**
   ```bash
   vim site/pages/home.md
   ```

3. **Set up payments** (optional):
   - Configure Stripe in Admin → Settings → Integrations
   - Create products in `site/products/`

4. **Deploy to production:**
   - Admin → Updates & Deploy
   - Choose Kamal (self-hosted) or Fly.io

---

## System Requirements

- **macOS:** 10.15+ (Catalina or later)
- **Linux:** Ubuntu 20.04+ or similar
- **RAM:** 4GB minimum, 8GB recommended
- **Disk:** 2GB for Roe + content

---

## Getting Help

- **Documentation:** See `AGENTS.md` in the repository
- **Issues:** https://codeberg.org/waotw/roe/issues
- **Discussions:** Check the Codeberg repository discussions

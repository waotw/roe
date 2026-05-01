# Phase 2: Directory Structure Setup

## Overview
This phase transforms Roe from a standard Rails structure to a versioned structure that supports the staged update system.

## What Changes

### Before (Standard Structure)
```
/roe/
  app/
  bin/
  config/
  site/
  ... (all Rails files)
```

### After (Versioned Structure)
```
/roe/
  current/          # Rails app moved here
    app/
    bin/
    config/
    .git/           # Git repo moved here
    ...
  site/             # Your content (unchanged)
  staging/          # Empty (for future updates)
  static_site/      # Empty (for static output)
  site_backups/     # Empty (for backups)
  roe.sh            # Launcher script
  VERSION           # Version tracking
  README.md         # Documentation
```

## How to Run Phase 2

### Step 1: Run the Setup Script
```bash
./setup_phase2.sh
```

This will:
- Create `current/`, `staging/`, `static_site/`, `site_backups/` directories
- Move Rails code to `current/`
- Move `.git/` to `current/`
- Create `VERSION` file at root
- Update `.gitignore`
- Create new `README.md`

### Step 2: Test the New Structure

**Option A: Using roe.sh (recommended)**
```bash
./roe.sh start
```

**Option B: Manual (from root)**
```bash
cd current && bin/rails server
```

### Step 3: Verify Everything Works
- [ ] Server starts without errors
- [ ] Can access http://localhost:3000
- [ ] Admin panel loads
- [ ] Can create/edit posts, pages
- [ ] Media uploads work
- [ ] Static site generation works (outputs to `static_site/`)
- [ ] Backups work (outputs to `site_backups/`)

### Step 4: Commit the Changes
```bash
cd current  # Git is now in here
git add -A
git commit -m "refactor: Restructure to versioned directory layout

- Move Rails application to current/ directory
- Move .git to current/
- Add staging/, static_site/, site_backups/ directories
- Add roe.sh launcher script
- Add VERSION file
- Update for Phase 2 staged update system"
```

## What Stays in Root

These items remain at `/roe/` level (outside of `current/`):

- `site/` - Your content (posts, pages, media, config)
- `site_backups/` - Automatic backups
- `static_site/` - Static site output
- `staging/` - For future updates
- `roe.sh` - Launcher script
- `VERSION` - Version tracking
- `README.md` - Documentation
- `.zed/` - Editor config
- `.opencode/` - Tooling
- `.github/` - Workflows
- `.kamal/` - Deployment
- `.bundle/` - Bundle config

## What Moves to current/

Everything else moves into `current/`:

- `app/`, `bin/`, `config/`, `db/`, `lib/`, `log/`, `public/`, `storage/`, `tmp/`, `vendor/`
- `docs/` - Documentation
- `Gemfile`, `Gemfile.lock`, `Rakefile`, `config.ru`, `Procfile`, etc.
- `Dockerfile`, `fly.toml`, `.dockerignore`, `.rubocop.yml`, `.ruby-version`
- `.git/` - Git repository

## Working with Git After Phase 2

**From root directory:**
- Git commands won't work (no .git here anymore)
- Work with files directly (site/, roe.sh, VERSION)

**From current/ directory:**
- Git commands work normally
- All git history preserved
- `git log`, `git status`, etc. work as expected

**Example workflow:**
```bash
# Edit site content (from root)
vi site/posts/my-post.md

# Commit code changes (from current/)
cd current
git add .
git commit -m "Fix bug in posts controller"
```

## Troubleshooting

### Issue: "command not found: rails"
**Solution**: You're in root directory. Either:
- Use `./roe.sh console` from root
- Or `cd current && bin/rails console`

### Issue: Server won't start
**Solution**: Check that you're in `current/` directory or using `roe.sh`:
```bash
./roe.sh status  # Check status
./roe.sh start   # Start server
```

### Issue: Site content not found
**Solution**: Verify site/ directory is at root level (not inside current/):
```bash
ls -la /roe/site  # Should exist
ls -la /roe/current/site  # Should NOT exist
```

## Next Steps (Phase 3)

After Phase 2 is complete and tested:

1. **Test update system** - Check for updates in Admin → Updates
2. **Download new version** - Clone to staging/
3. **Switch versions** - Test the atomic swap
4. **Verify rollback** - Test automatic rollback on failure

## Questions?

Refer to the main README.md created at root level after running setup_phase2.sh.

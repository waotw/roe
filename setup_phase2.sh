#!/bin/bash
# Roe CMS - Phase 2 Setup Script
# Transforms standard directory structure to versioned structure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROE_ROOT="$SCRIPT_DIR"

echo "🚀 Roe CMS - Phase 2: Directory Structure Setup"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if already in versioned structure
if [ -d "$ROE_ROOT/current" ]; then
    log_error "Already in versioned structure (current/ directory exists)"
    exit 1
fi

# Check if site/ exists
if [ ! -d "$ROE_ROOT/site" ]; then
    log_error "site/ directory not found. Are you in the correct directory?"
    exit 1
fi

log_info "Creating directory structure..."

# Create new directories
mkdir -p "$ROE_ROOT/current"
mkdir -p "$ROE_ROOT/staging"
mkdir -p "$ROE_ROOT/static_site"
mkdir -p "$ROE_ROOT/site_backups"

log_success "Created: current/, staging/, static_site/, site_backups/"

# Move Rails application to current/
log_info "Moving Rails application to current/..."

# List of items to move to current/
MOVE_TO_CURRENT=(
    "app"
    "bin"
    "config"
    "db"
    "lib"
    "log"
    "public"
    "storage"
    "test"
    "tmp"
    "vendor"
    "docs"
    "Gemfile"
    "Gemfile.lock"
    "Rakefile"
    "config.ru"
    "Procfile"
    "Procfile.dev"
    "Dockerfile"
    "fly.toml"
    ".dockerignore"
    ".rubocop.yml"
    ".ruby-version"
)

for item in "${MOVE_TO_CURRENT[@]}"; do
    if [ -e "$ROE_ROOT/$item" ]; then
        mv "$ROE_ROOT/$item" "$ROE_ROOT/current/"
        log_success "Moved: $item → current/"
    else
        log_warning "Not found: $item"
    fi
done

# Move .git if it exists
if [ -d "$ROE_ROOT/.git" ]; then
    log_info "Moving .git to current/..."
    mv "$ROE_ROOT/.git" "$ROE_ROOT/current/"
    log_success "Moved: .git → current/"
fi

# Create VERSION file at root
log_info "Creating VERSION file..."
cat > "$ROE_ROOT/VERSION" << 'EOF'
version: "0.1.0"
release_date: "2026-05-01"
channel: "stable"
repository: "https://git.sr.ht/~benjaminwelch/roe"
EOF

log_success "Created: VERSION"

# Update .gitignore at root to ignore new directories
log_info "Updating .gitignore..."
cat >> "$ROE_ROOT/.gitignore" << 'EOF'

# Roe versioned structure
/current/
/staging/
/static_site/
/site_backups/
EOF

log_success "Updated: .gitignore"

# Create README at root explaining the structure
log_info "Creating README..."
cat > "$ROE_ROOT/README.md" << 'EOF'
# Roe CMS

Roe is a file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store.

## Directory Structure

This is a **versioned** Roe installation:

```
/roe/
  current/          # Current Roe version (Rails app)
  staging/          # New version during updates
  site/             # Your content (posts, pages, media, config)
  static_site/      # Generated static site output
  site_backups/     # Automatic backups
  roe.sh            # Server management script
  VERSION           # Current version info
```

## Quick Start

```bash
# Start the server
./roe.sh start

# Or from current/ directory
cd current && bin/rails server
```

## Managing Your Site

- **Content**: Edit files in `site/` directory
- **Admin**: Visit http://localhost:3000/admin
- **Updates**: Use Admin → Updates to check for and install updates
- **Backups**: Automatic backups stored in `site_backups/`

## Documentation

See `current/docs/` for full documentation.

## License

[Your license here]
EOF

log_success "Created: README.md"

echo ""
echo "================================================"
log_success "Phase 2 Setup Complete!"
echo ""
echo "Next steps:"
echo "  1. Review the changes"
echo "  2. Test by running: cd current && bin/rails server"
echo "  3. Commit the new structure"
echo ""
log_info "Your directory structure is now:"
echo "  /roe/"
echo "    current/      ← Rails app (was root)"
echo "    site/         ← Your content (unchanged)"
echo "    staging/      ← Empty (for future updates)"
echo "    static_site/  ← Empty (for static output)"
echo "    site_backups/ ← Empty (for backups)"
echo "    roe.sh        ← Launcher script"
echo "    VERSION       ← Version info"
echo ""

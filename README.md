# Roe CMS

Roe is a file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store.

## Installation

**Prerequisites:** Ruby 3.2.2, Git

```bash
git clone git@codeberg.org:waotw/roe.git
cd roe
./bin/setup
```

See [INSTALL.md](INSTALL.md) for detailed installation instructions and troubleshooting.

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

Roe is free to use in development forever. Deployment requires a license.

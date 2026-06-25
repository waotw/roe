# Roe

Roe is a file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store.

> **Beta:** Roe is currently in beta. Download it before 1.0 and you'll be eligible for a free commercial license. See the [license](site/pages/license.md) for details.

## Installation

**Prerequisites:** Ruby 3.2.2, Git

```bash
git clone git@codeberg.org:waotw/roe.git
cd roe
./bin/setup
```

Full installation instructions and troubleshooting are at [go-roe.com/documentation](https://go-roe.com/documentation).

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

## Documentation & Support

- **Documentation:** [go-roe.com/documentation](https://go-roe.com/documentation)
- **Support:** [go-roe.com/support](https://go-roe.com/support)

## License

Roe is free for personal and development use. Commercial use requires a license. See [site/pages/license.md](site/pages/license.md) for the full agreement.

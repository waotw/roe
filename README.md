# Roe

Roe is a file-backed CMS/blog with first-class support for podcasts, paid memberships, newsletters, and a built-in store.

> **Beta:** Roe is currently in beta. Download it before 1.0 and you'll be eligible for a free commercial license. See the [license](site/pages/license.md) for details.

## Installation

Only install Roe with `git` if you plan on developing Roe itself. To build sites with Roe, download it [here](https://go-roe.com) and follow this document: [Installing Roe](https://go-roe.com/documentation/guide-installation)

If you plan to delelop Roe: use the following command and it will install all dependencies.

```bash
git clone git@codeberg.org:waotw/roe.git
cd roe
./bin/setup
```

~Full documentation, instructions and troubleshooting are at [go-roe.com/documentation](https://go-roe.com/documentation).

## Requirements

Roe runs on **macOS** and **Linux**. To launch Roe you need:

- **Ruby 3.2.2** — managed for you with [mise](https://mise.jdx.dev)
- **Git**
- **A C compiler & build tools** (to install Ruby and gems)
  - macOS: Xcode Command Line Tools
  - Linux: `build-essential` (or your distribution's equivalent)

The install script (`./roe.sh check`) installs and configures all of the above for you.

Roe's Ruby gems are installed automatically by Bundler during setup — there's nothing to install by hand.

## Optional libraries

Install these to turn on extra features. Roe runs fine without them.

- **libvips** — image optimization (resizes and compresses your images on upload)
- **ImageMagick** — reads image dimensions for social/SEO image tags

## Directory Structure

```
/roe/
  current/          # Current Roe version (Rails app)
  site/             # All your site content & config (posts, pages, media, config, databases, etc.)
  roe.sh            # Server management script
  start.command     # Double-click on macOS to launch Roe
  README.md         # Basic info about Roe and helpful links
  LICENSE           # License file, links to full license
  VERSION           # Current version info
```

## Quick Start

```bash
# From roe's root folder, start the install and setup
./roe.sh check
```

```bash
# Start the server from Root directory
./roe.sh start
```

## Managing Your Site

- **Admin**: Visit http://localhost:3000/admin
- **Content**: Edit files in Admin with The Editor or in `site/` directory with text editor of your choice
- **Updates**: Use Admin → Updates to check for and install updates
- **Backups**: Automatic backups stored in `site_backups/` when using Site Sync and Deploy from Admin

## Documentation & Support

- **Documentation:** [go-roe.com/documentation](https://go-roe.com/documentation)
- **Support:** [go-roe.com/support](https://go-roe.com/support)

## License

Roe is open-source software with commercial-use restrictions. During the beta period (versions < 1.0), commercial use is not licensed unless permission is given in writing from licensor. See [License](https://go-roe.com/license) for the full agreement.

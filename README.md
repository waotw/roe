# Roe

Roe is a file-backed CMS with first-class support for blogs, podcasts, paid memberships, newsletters, and a built-in store — plus image galleries, built-in search, and automatic SEO & social images.

> **Beta:** Roe is in beta until 1.0 is released. Commercial use is not permitted until 1.0. See the [license](https://go-roe.com/license) for details.

## Installation

Only install Roe with `git` if you plan on developing Roe itself. To build sites with Roe, download it [here](https://go-roe.com) and follow this document: [Installing Roe](https://go-roe.com/documentation/roe/guide-installation)

If you plan to develop Roe: use the following command and it will install all dependencies.

```bash
git clone https://codeberg.org/waotw/roe.git
cd roe
./bin/setup
```

Full documentation, instructions and troubleshooting are at [go-roe.com/documentation](https://go-roe.com/documentation).

## Requirements

Roe runs on **macOS**, **Linux**, and **Windows via WSL2**. To launch Roe you need:

- **Ruby 3.2.2** — managed for you with [mise](https://mise.jdx.dev)
- **Git**
- **A C compiler & build tools** (to install Ruby and gems)
  - macOS: Xcode Command Line Tools
  - Linux: `build-essential` (or your distribution's equivalent)

The install script (`./roe.sh check`) installs and configures all of the above for you.

Roe's Ruby gems are installed automatically by Bundler during setup — there's nothing to install by hand.

## Windows

Roe runs on Windows through **WSL2**, Microsoft's built-in Linux environment. Inside
WSL, Roe is a Linux install — the same installer, the same commands.

In PowerShell, as Administrator:

```powershell
wsl --install
```

That enables the Windows features, installs the Linux kernel, and sets up Ubuntu.
Restart when it asks. Then open Ubuntu from the Start menu and install Roe as normal:

```bash
cd ~ && curl -fsSL https://go-roe.com/install | bash
```

Roe is then at `http://localhost:3000` in your normal Windows browser — WSL2
forwards the port for you.

### Install Roe in your Linux home folder, not on the C: drive

This is the one thing that matters. Install Roe under `~` (as above), **not** under
`/mnt/c`. Windows drives can't store Unix file permissions, so Roe's launcher never
becomes executable — and file-change detection doesn't see edits made from Windows,
so your content quietly stops syncing. Roe checks for this and stops with
instructions rather than letting you find out later.

Your files are still fully reachable from Windows. In File Explorer:

```
\\wsl$\Ubuntu\home\<your-username>\roe
```

To edit them, install [VS Code](https://code.visualstudio.com) with the **WSL**
extension, then from the Ubuntu terminal:

```bash
code ~/roe
```

That runs the editor on Windows against the files on the Linux side, which keeps
permissions and file watching working.

## Optional libraries

Install these to turn on extra features. Roe runs fine without them.

- **libvips** — image optimization (resizes and compresses your images on upload)
- **ImageMagick** — reads image dimensions for social/SEO image tags

## Directory Structure

```
/roe/
  current/          # Current Roe version (Rails app)
  site/             # All your site content & config (posts, pages, media, config, databases, etc.)
  backups/          # Local and live-site backups (created by Site Sync)
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
- **Backups**: Automatic backups stored in `backups/` when using Site Sync and Deploy from Admin

## Documentation & Support

- **Documentation:** [go-roe.com/documentation](https://go-roe.com/documentation)
- **Support:** [go-roe.com/support](https://go-roe.com/support)

## License

Roe is open-source software with commercial-use restrictions. During the beta period (versions < 1.0), commercial use is not licensed unless permission is given in writing from the licensor. See [License](https://go-roe.com/license) for the full agreement.

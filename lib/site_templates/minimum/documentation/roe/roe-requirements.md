---
title: What Roe Installs
status: published
url_name: roe-requirements
tags: reference, requirements
related:
  - guide-installation
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# What Roe installs

You don't need to read this page to install Roe. The [installer](/documentation/guide-installation) sets everything up for you and tells you when each part is ready.

This page has two parts. The first is for anyone curious about what landed on their computer. The second is for developers who want the full stack — every tool, gem, and file the installer touches.

## For users

When you install Roe, it sets up the [Ruby](/documentation/glossary#ruby) programming language and a few supporting tools. Roe is written in Ruby, so this is what lets it run. The installer does all of it for you — there's nothing to install by hand.

It also installs a set of Ruby [gems](/documentation/glossary#gems): small add-on libraries Roe depends on, like the web server that serves your pages and the database that holds your content. You don't need to know them by name — the installer handles them, and you can read about each one [below](#for-developers)

### What changes on your computer

A full install:

- installs a version of Ruby, kept separate from any other Ruby you may already have
- adds one line to your terminal's startup file, so Roe's Ruby is ready in new windows
- creates your `/site` folder — your content, settings, and database
- generates a [master key](/documentation/glossary#master-key) that keeps your secrets safe
- creates your admin account

Everything runs on your own computer. Roe needs no separate accounts and no outside servers.

### Optional extras

Two features stay off until you add the tools that power them. Roe runs fine without either:

- **Sharper, smaller images** — Roe can resize and compress your images as you upload them.
- **Better social previews** — Roe can read your images' dimensions to build richer link previews for social media and search.

Roe's setup offers to help you turn these on, or you can add them later.

## For developers

This section covers the full stack — what Roe requires, the gems it installs, and what it deliberately leaves out.

### Required to run

Roe is built with [Ruby](/documentation/glossary#ruby), so most of what it installs exists to run Ruby and Roe's code. Four things are required:

| What | Why Roe needs it | How it arrives |
|------|------------------|----------------|
| **Ruby 3.2.2** | The language Roe is written in. Nothing else runs until Ruby is in place. | Installed and pinned by [mise](/documentation/glossary#mise) (below) |
| **mise** | A version manager that installs the exact Ruby version Roe needs, without disturbing any other Ruby on your system. | `brew install mise`, or the standalone installer `curl https://mise.run \| sh` |
| **[Git](/documentation/glossary#git)** | Roe's built-in updater uses Git to fetch new releases. | `xcode-select --install` or `brew install git` (macOS); your package manager (Linux) |
| **[A C compiler and build tools](/documentation/glossary#build-tools-c-compiler)** | Needed to build Ruby's libraries and any Ruby add-ons written in C. | Xcode Command Line Tools (macOS); `build-essential` or your distribution's equivalent (Linux) |

The install script, `./roe.sh check`, checks for each of these, installs whatever is missing, and configures it.

### How Ruby is installed

Roe pins its Ruby version in `current/.ruby-version`. mise reads that file and installs the matching Ruby — a precompiled build when one is available, or built from source if not. That version becomes your global Ruby, and mise keeps it separate from any system Ruby, so nothing you already have breaks.

To make the pinned Ruby available in new terminal windows, the installer adds a `mise activate` line to your shell's startup file (`~/.zshrc` on macOS, `~/.bashrc` on many Linux systems).

If you already have [Homebrew](/documentation/glossary#homebrew), the installer uses it to install mise and Git. If you don't, Roe does not require it — mise's standalone installer needs nothing but `curl`. Roe never installs Homebrew for you.

### The Ruby [gems](/documentation/glossary#gems) Roe installs

[Bundler](/documentation/glossary#bundler) installs Roe's gems automatically from the `Gemfile` during setup. Roe is a [Rails](/documentation/glossary#ruby-on-rails-rails) app, so it also pulls in the gems any Rails app needs — the web server, the database adapter, and so on. The gems below are the ones that give Roe its own features, beyond what Rails provides.

**Content and Markdown**

- **kramdown** and **kramdown-parser-gfm** — turn your Markdown into HTML
- **front_matter_parser** — read the YAML settings at the top of each content file
- **nokogiri** — parse and rewrite HTML for feeds, imports, and link previews
- **rss** — build the RSS and Atom feeds for the blog and podcasts
- **listen** — watch your `site/` folder and re-sync when files change

**Images**

- **image_processing** — generate resized image variants
- **ruby-vips** and **mini_magick** — the Ruby bindings for the libvips and ImageMagick libraries
- **fastimage** — read image dimensions in pure Ruby, with no system libraries

**Email and payments**

- **postmark-rails** — send transactional and broadcast email through Postmark
- **premailer-rails** — inline CSS so email renders in every client
- **stripe** — take payments and manage paid memberships

**Accounts, backups, and transfer**

- **bcrypt** — hash member and admin passwords
- **rubyzip** — read and write the `.zip` archives Roe uses for backups and imports
- **net-sftp** and **net-ftp** — move files to and from a live server
- **webrick** — serve a local preview of the generated static site

**Install-time admin setup**

- **tty-prompt**, **tty-box**, and **tty-spinner** — draw the terminal screens that create your admin account during setup

**Styling**

- **tailwindcss-rails** and **tailwindcss-ruby** — style the admin interface with a standalone Tailwind binary, with no [Node.js](/documentation/glossary#nodejs)

The underlying **libvips** and **ImageMagick** libraries are optional — see below.

### What Roe deliberately avoids

Some tools common to other web software are absent by design:

- **No Node.js, npm, or Yarn.** Roe runs its JavaScript with importmaps and styles itself with a standalone Tailwind binary.
- **No separate database server.** SQLite stores everything in files inside your `/site` folder.
- **No [Redis](/documentation/glossary#redis) or other background-job service.** The Solid gems use SQLite for that too.

Keeping the stack small is why a Roe site can live entirely in one folder.

### Optional libraries

Not installed by default; Roe runs fine without them. Install them to enable the extra features noted above:

- **[libvips](/documentation/glossary#libvips)** — resizes and compresses images on upload
- **[ImageMagick](/documentation/glossary#imagemagick)** — reads image dimensions for social and SEO image tags

To see what's installed at any time, run `./roe.sh status` from your Roe folder.

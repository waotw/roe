---
roe_version: 0.0.20
title: Configuration & Defaults with YAML
status: draft
---

# Configuration & Defaults

In the [Settings](/admin/configs) section of the Admin, you can do the following:

- Edit global site Settings
  - site name
  - site tagline
  - global author
  - add logo
  - add custom fonts
- Edit Defaults for Cards and Collections
  - Edit Button Templates for Cards and Collections

## Site Configuration

The `site.yml` file contains site-wide metadata used throughout your site and in RSS/Atom feeds:

```yaml
# Site Configuration
title: My Site
description: A description of my site
author: Your Name

# Branding
logo: logo.svg
logo_style: beside_text  # Options: beside_text, replace_text
favicon: favicon.ico

# Custom Fonts (optional)
fonts:
  heading:
    family: "My Heading Font"
    regular: HeadingFont-Regular.woff2
    bold: HeadingFont-Bold.woff2
  
  body:
    family: "My Body Font"
    regular: BodyFont-Regular.woff2
    bold: BodyFont-Bold.woff2
    italic: BodyFont-Italic.woff2
    bold_italic: BodyFont-BoldItalic.woff2
  
  mono:
    family: "My Mono Font"
    regular: MonoFont-Regular.woff2
```

### Available Settings

- **title**: Your site's name (used in feeds, page titles)
- **description**: Brief description of your site (used in feed metadata)
- **author**: Default author name (used in feeds and metadata)
- **logo**: Filename of logo image from `content/system/assets/images/`
- **logo_style**: How to display the logo (`beside_text` or `replace_text`)
- **favicon**: Filename of favicon from `content/system/assets/images/`
- **fonts**: Custom font configuration (optional)

### Custom Fonts

You can configure custom fonts for three roles: heading, body, and mono (code). Each font role supports these variants:

- **regular** (required)
- **bold** (optional)
- **italic** (optional)
- **bold_italic** (optional)

Font files should be uploaded to `content/system/assets/fonts/`. Supported formats:
- `.woff2` (recommended for best compression)
- `.woff`
- `.ttf`
- `.otf`

The CMS automatically generates the necessary CSS `@font-face` rules and CSS variables for your fonts.

## Default Configurations

The `defaults/` directory contains YAML files that define default behavior for [collections](collections) and [cards](cards). The defaults are used unless you specify something different. 

### How Defaults Work

1. **System Default**: Defined in `defaults/collections.yml` and `defaults/cards.yml`
2. **Content Override**: Specified in individual cards/collections
3. **Priority**: Content-specific values always override system defaults

**Example:**
````yaml
# In defaults/collections.yml
default_limit: 10

# In your content
```collection
limit: 5  # This overrides the default of 10
```
````

## Cards Defaults

`defaults/cards.yml` controls default behavior for card components.

[See detailed card configuration documentation →](cards)

### Collections Defaults

`defaults/collections.yml` controls default behavior for content collections (lists of posts, pages, etc.).

[See detailed collection configuration documentation →](collections)

## System Assets

System assets (fonts and images for branding) are stored separately from regular media files:

- **Fonts**: `content/system/assets/fonts/` - Font files referenced in `site.yml`
- **Images**: `content/system/assets/images/` - Logos, favicons, and other branding images

These directories are created automatically if they don't exist.

## Editing Configurations

### Via Admin Interface

Navigate to **Settings** in the admin navigation to manage all configuration files:

1. Click **Settings** in the admin menu
2. Select the configuration file you want to edit (site.yml, cards.yml, or collections.yml)
3. Edit the YAML content in the text editor
4. Click **Save Configuration**

The editor includes:
- Line counting
- Tab key support (2-space indentation)
- YAML syntax validation
- Error messages for invalid syntax

#### Managing System Assets

When editing `site.yml`, you can manage fonts and images:

1. Click **Fonts** or **Global Images** in the editor toolbar
2. Upload new files or manage existing ones
3. Click **Copy Filename** to get the exact filename
4. Paste the filename into your `site.yml` configuration

### Via File System

You can also edit configuration files directly in `content/system/`:

1. Open the file in your text editor
2. Make changes following [YAML](https://yamline.com/tutorial/) syntax
3. Save the file
4. Changes are automatically detected and applied

**Note**: Changes made via the admin interface or file system are immediately synced to the database and cached for performance.

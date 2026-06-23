---
title: "Global → Site"
status: published
tags: settings
---

# Global Site Settings

In the [Settings → Global → site.yml](/admin/configs/site/edit) 

## Site
- `Site title` - used in feeds, page titles, emails
- `Site URL` - used in emails and feeds
- `Site Description` - used in feed metadata
- `Author` - used in feeds and metadata

### Branding
- `Logo` - Image file used in the site's header if you prefer to use an image instead of text
- `Logo style` - How to display the logo (`beside_text` or `replace_text`)
    - This can be styled in your theme's CSS
- `Favicon` - Image file used for favicon

### Theme

Set your active theme. You can also do this by activating a theme here [Themes](/admin/themes) which will update this setting.

### Static Site Settings

- Toggle on/off static-site generation
    - When turned on, all traffic is sent to the static site. (currently, Members, Payments and other features require a database to work and so aren't supported for static-site generation)

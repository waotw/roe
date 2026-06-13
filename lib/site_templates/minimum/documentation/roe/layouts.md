---
roe_version: 0.0.20
title: Layouts
status: published
---

# Layouts

`Admin → Layouts`

Layouts are also just markdown files:

- `navigation` = logo, site links, anything you want at the top of every page
- `footer` = copywrite, extra links, anything you want at the bottom of every page
- `sidebar` = enable the sidebar by creating this file

## Editing a layout

At the top of the Layout edit page, you'll see a `SHOW LINKS` button. This will show you all the active pages for your site. Makes it easier to find the exact url that you need for links.

## Navigation

`{: .site-logo}` is used under the site name by default. This adds a CSS class to the site name so it can be targeted in the [themes](themes). This allows you to replace the logo with an SVG or add an icon, etc. The settings to add a site logo are under: [Settings → Site → Branding](/admin/configs/site/edit).

## Footer

Nothing special here. Just add the links and copywrite notice if needed.

## Sidebar

To enable the sidebar, click `Create`. This layout has options you'll see them in the front matter[^1] at the top of the file.

- `position` = use `left` or `right` to move the sidebar to either side of the site.
- `scope` = which sources (`pages`, `posts`, `documentation`) show the sidebar. It's set to `pages` by default. This means it will only show up on pages, not posts.


[^1]: Frontmatter is a block of metadata at the start of a Markdown file, enclosed by `---` at the top/bottom. It provides information about the document that is used by the system but isn't visible when viewing the page/post.

---
title: "Layouts"
status: published
tags: admin
---

# Layouts

[`Admin → Layouts`](/admin/layouts)

Layouts are all the parts of your site that are not the main content section:

- `navigation` = logo, site links, anything you want at the top of every page
- `footer` = copyright, extra links, anything you want at the bottom of every page
- `sidebar` = enable the sidebar by creating this file, disable this on specific Pages or Post with `show_sidebar: false`

## Editing a layout

At the top of the Layout edit page, you'll see a `SHOW LINKS` button. This will show you all the active pages for your site. Makes it easier to find the exact `url_name` that you need for links.

## Navigation

You can add any links or text you want to this layout and they'll show up at the top of your page.

### Add dynamic navigation

You can avoid manually adding Pages and links to your navigation with a Collection and the [`menu` template](/documentation/roe/collections_templates#when-to-use-the-menu-template). There are 2 ways to do this:

#### 1. Create a `menu` Collection

When you set the Colleciton `template` to `menu`, this Collection will render only links as a list. You can use the `style` to give them a `vertical` or `horizontal` layout. Here's an example:

````markdown
```collection
```collection
source: pages
template: menu
style: horizontal
order: blog, blog-tags, podcast, about, support, documentation, store
```
```
````

Add the `url_name`s for each page you want to add. The links will show up in the exact order you see here.

#### 2. Name a Collection so content can be sent to it

You can give any Collection a name and then send Pages, Posts, Products to that Collection. Let's say I'm using the Collection above for navigation on my site but I've added a new page. I can "send" that new page to this Collection by:

1. Giving the Collection a name: `collection: nav`
2. Adding this to the metadata for my new Page with: `collection: nav`

Now, the new page I just created is "sent" to the navigation. You will control the order with `order` in the Collection itself. The new page will be added to the end unless you give it a specific place.

### How to style your Logo / Site Title

`{: .site-logo}` is used under the site name by default. This adds a CSS class to the site name so it can be targeted in the [themes](themes). This allows you to replace the logo with an SVG or add an icon, etc. The settings to add a site logo are under: [Settings → Site → Branding](/admin/configs/site/edit).

## Footer

Nothing special here. Just add the links and copyright notice if needed. A [`menu` Collection](#add-dynamic-navigation) might come in handy here as well.

## Sidebar

To enable the sidebar, click `Create`. This layout has options you'll see them in the front matter[^1] at the top of the file.

- `position` = use `left` or `right` to move the sidebar to either side of the site.
- `scope` = which sources (`pages`, `posts`, `documentation`) show the sidebar. It's set to `pages` by default. This means it will only show up on pages, not posts.

Again, a [`menu` Collection](#add-dynamic-navigation) would be useful here if you want to add a specific list of links.

[^1]: Frontmatter is a block of metadata at the start of a Markdown file, enclosed by `---` at the top/bottom. It provides information about the document that is used by the system but isn't visible when viewing the page/post.

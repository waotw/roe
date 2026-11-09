---
title: "Layouts"
status: published
tags: admin
---

# Layouts

Edit layouts here: [`Admin → Layouts`](/admin/layouts)

Roe has two kinds of layouts:

- [Site Layouts](#site-layouts)
- [Content Layouts](#content-layouts)

## Site Layouts

Site Layouts are all the parts of your site that are not the main content section:

- [`header`](#header) = logo, site links, anything you want at the top of every page
- [`footer`](#footer) = copyright, extra links, anything you want at the bottom of every page
- [`sidebar`](#sidebar) = add a sidebar to your site

## Editing a layout

1. Open the layout you wish to edit on the [Layouts](/admin/layouts) page.
2. Add links, menus, logo, etc.
3. Click `SAVE`
4. The layout changes are now live.

### How to add navigation

There is an `ADD NAVIGATION` button which helps you build your navigation. It opens a form with all your page links on the left and settings on the right.

The navigation builder inserts `menu` Collections (recommended way to create lists of links) or markdown links if you prefer working in markdown.

#### Edit navigation

If you already have navigation and want to edit it, place the caret/cursor over that section and the `ADD NAVIGATION` button becomes `EDIT NAVIGATION`. This allows you to update existing links or `menu` Collections in the builder.

### `menu` Collections and dynamic navigation

`menu` Collections allow you to create a list of links that can change without you having to edit them. More info: [`Collection Templates`](/documentation/roe/collections_templates#when-to-use-the-menu-template)

#### 1. Create a `menu` Collection

Use the `ADD NAVIGATION` button to open the navigation builder:

1. Click pages on the left to add them to your navigation
2. Change the order as needed (on the right)
3. Give the Collection a name, it defaults to `nav`.
4. Choose the style (vertical or horizontal)

<mark>Note: </mark> you can add `show_active: true/false` or toggle it on in the builder and this will add styling to the link when you're on that page. Often this is called `active`. This is on by default in the `header` and off by default in `sidebar` and `footer`.

Here's an example of the block that this will insert:

````markdown
```collection
collection: nav
template: menu
style: horizontal
order: blog, blog-tags, podcast, about, support, documentation, store
```
````

#### 2. Name a Collection so content can be sent to it

You can give any Collection a name (`nav` in the example above) and then send Pages, Posts, Products to that Collection. Let's say I'm using the Collection above for navigation on my site but I've added a new page. I can "send" that new page to this Collection by:

1. Giving the Collection a name: `collection: nav`
2. Adding this to the metadata for my new Page with: `collection: nav`

Now, the new page I just created is "sent" to the `nav` Collection. You will control the order with `order` in the Collection itself. The new page will be added to the end unless you give it a specific place.

## Header

### How to style your Logo / Site Title

`{: .site-logo}` is used under the site name by default. This adds a CSS class to the site name so it can be targeted in the [themes](/documentation/roe/themes). This allows you to replace the logo with an SVG or add an icon, etc. The settings to add a site logo are under: [Settings → Site → Branding](/admin/configs/site/edit).

## Footer

Nothing special here. Just add the links and copyright notice if needed. A [`menu` Collection](#menu-collections-and-dynamic-navigation) might come in handy here as well.

## Sidebar

You may want to use the sidebar for navigation as well and just keep your logo or site title in the `header` Layout.

To enable the sidebar, click `Create`. Its options live in the frontmatter[^1] at the top of the file:

- `position` = use `left` or `right` to move the sidebar to either side of the site.
- `scope` = which sources (`pages`, `posts`, `products`, `documentation`) show the sidebar. It's set to `pages` by default. This means it will only show up on pages, not posts.
- `mobile` = how the sidebar behaves once the screen is too narrow to show it beside your content. Set to `hidden` by default.
- `mobile_style` = the orientation of a `menu` Collection after the sidebar has moved on a narrow screen. Optional.

Again, a [`menu` Collection](#menu-collections-and-dynamic-navigation) would be useful here if you want to add a specific list of links.

### The sidebar on mobile

By default the sidebar disappears once the screen is too narrow to show it beside your content. Set `mobile` to keep it in view instead:

- `hidden` (default) = the sidebar is hidden on narrow screens.
- `top` = the sidebar moves under the header as a horizontal strip that stays visible.
- `bottom` = the sidebar moves below your content, full width, and stays visible.

When the sidebar holds a `menu` Collection, its links take the orientation that fits the new spot: `top` lays them out in a row, `bottom` keeps them in a column. Set `mobile_style` to override that:

- `horizontal` = lay the links out in a row.
- `vertical` = stack the links in a column.

If your sidebar is the site navigation and should stay on screen, `mobile: top` is the usual choice.

## Content Layouts

Roe uses sensible defaults, but if you would like to customize the layout of your pages and posts, you can enable content layouts here: [Settings → Roe → content](http://roe.roe:3000/admin/configs/content/edit)

Content layouts do one thing: they allow you to structure content (pages, posts, etc.). There are 2 parts of the layout, blocks and `[boxes]`:

- A block is a group of `[boxes]`. A blank line creates a new block.
- A `[box]` represents an element in the layout. You can group `[boxes]` by putting them next to each other. This gives them their own `<div>`.

==Note:== As with everything in Roe, you can override global settings locally. In the case of content layouts, you can add elements to the post or page itself and these will be used instead of the ones in the layout. For example, a `[player]` might be at the top of an audio post but be at the bottom in the `audio.txt` layout. The post will always win and override the layout. The top `[player]` is used.

### Edit a content layout

The layout editor has the layout on the left and a preview of the HTML that will be written on the right. The best way to learn how the layouts work is to:

1. Open a layout, perhaps `article.txt`
2. Click on a line or `[box]` in the editor
3. The related HTML will be ==highlighted== in the HTML section on the right. The information under DETAILS will update and explain what that element is doing.
4. Move things around and save (you can always go back to the default)
5. Refresh the article you have open and you'll see the changes

Open the diagram in the DETAILS section for a visual guide.

#### Add `[boxes]`

All available `[boxes]` are listed in the "BOXES" section above the editor. Click a box to add it to the layout at the caret/cursor.

### Structure of a content layout

A content layout with the `[body]` box and nothing else is the simplest layout possible. It renders what is in the page or post only.

- The topmost block above the `[body]` box is the `<header>`.
- The bottommost block below the `[body]` box is the `<footer>`.
- All other blocks are groups.

You can add CSS classes to blocks and rows. To add a CSS class to a block, put the name of the class on it's own line at the top, followed by a `:`.

```markdown
post-header:
  post-header-top: [title] [feed links]
  [subtitle]
  post-meta: [date] [author]
  [image]
```

This gives this block the CSS class `post-header`. You can also add a CSS class to a row. Notice `post-meta:` in the example above. It wraps the `[date]` and `[author]` boxes in a `<div>` with the class of `post-meta`.

### Create a content layout

You can add your own layouts. On the Admin → Layouts page, type the name and click `NEW LAYOUT`. Then add `layout: <layout_name>` to the frontmatter of the page or post and it will use this layout instead of the default.

[^1]: Frontmatter is a block of metadata at the start of a Markdown file, enclosed by `---` at the top/bottom. It provides information about the document that is used by the system but isn't visible when viewing the page/post.

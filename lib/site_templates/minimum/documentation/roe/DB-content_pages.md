---
title: Pages
status: published
tags: content
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Pages

A Roe site is mostly [Markdown](/documentation/glossary#markdown) and [YAML](/documentation/glossary#yaml) files. There are 4 sources of content in Roe: Pages, [Posts](/documentation/posts), [Products](/documentation/products) (if you've enabled the Store) and Documentation.

Your Page files are in the `/site/pages` folder in your `Roe` folder (where you've installed Roe).

## Pages in Roe

Pages are for static content — things that don't change often and aren't part of a chronological feed:

- About page
- Contact page
- Homepage
- Legal pages (Privacy, Terms)
- Member pages (Sign up, Sign in, etc.)

Pages don't have dates and don't appear in RSS feeds or post Collections.

## Creating Pages

Create a new page in the [Admin → Pages](/admin/pages) section or add a `.md` file directly to `/site/pages`.

### Required Metadata

```yaml
---
title: About Me
status: published
---
```

### Common Metadata Fields

| Field | Description |
|-------|-------------|
| `title` | Page heading (required) |
| `subtitle` | Secondary heading |
| `url_name` | Custom URL slug (auto-generated from title if not set) |
| `status` | `draft`, `published`, or `unlisted` |
| `excerpt` | Short description |
| `image` | Featured image path |

See [Metadata Fields](/documentation/metadata-fields) for the full list.

## Special Pages

### Homepage

Create a page with `url_name: home` to use it as your homepage:

```yaml
---
title: Welcome
url_name: home
status: published
---
```

If no homepage exists, Roe shows a default empty-site message.

### 404 Page

Create a page with `url_name: 404` to customize your not-found page.

### Member Pages

When you enable [Members](/documentation/members), Roe generates pages for sign up, sign in, upgrade, and more. These live in `/site/pages/members/` and are regular Markdown files you can edit.

## Pages vs Posts

| | Pages | Posts |
|---|---|---|
| **Purpose** | Static content | Timed content (articles, episodes) |
| **Date** | No date | Has publish date |
| **Feeds** | Not included | Included in RSS/Atom |
| **Collections** | Can be included | Primary collection source |
| **URL** | `/page-name` | `/posts/post-name` or custom |

## Editing Pages

Use [The Editor](/documentation/the-editor) to write and format page content. Pages support all Roeanji features: [cards](/documentation/cards), [collections](/documentation/collections), [galleries](/documentation/galleries), and more.

## Navigation

Add pages to your site's navigation in [Admin → Layouts](/admin/layouts):

1. Go to **Layouts**
2. Under **Navigation**, add links to your pages
3. Save

Pages appear in the order you specify.

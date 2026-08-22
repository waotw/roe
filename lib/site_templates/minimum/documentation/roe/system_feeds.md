---
title: Feeds (RSS & Atom)
status: published
tags: system
related:
  - podcasts
  - posts
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Feeds

Roe automatically generates RSS and Atom feeds for your published posts. These are ready to use from day one — no configuration needed.

## Feed URLs

| Format | URL |
|--------|-----|
| RSS 2.0 | `/feed.xml` or `/feed` |
| Atom | `/feed.atom` |

Both feeds include the 20 most recent published posts, ordered by date.

## What’s Included

Feeds include all published posts with `published_to: site` or `published_to: both`. Posts set to `published_to: newsletter` only (or `status: draft` / `status: unlisted`) are excluded.

Each feed entry includes:

- **Title** — from `title`
- **Link** — the post’s public URL
- **Description** — resolved in this order:
  1. `excerpt` if set
  2. `subtitle` if set (no excerpt)
  3. First paragraph of the post content, truncated to 200 characters
- **Date** — from `date`
- **Author** — from `author` (if set on the post)
- **GUID** — the post’s full URL (permanent link)

## Feed Metadata

The feed’s channel-level title, description, link, and author come from your site settings: [Admin → Settings → site.yml](/admin/configs/site/edit).

| Feed field | Source |
|------------|--------|
| Channel title | `title` in site.yml |
| Channel description | `description` in site.yml |
| Channel link | `url` in site.yml |
| Managing editor | `author` in site.yml |

## Custom Feeds

The `/feed` above covers every post. To publish a narrower feed — one post type, one tag, a curated set — turn on custom feeds and define them.

Enable the feature from [Admin → Settings](/admin/configs) with **Enable Custom Feeds**. That creates `site/system/features/feeds.yml` (seeded with one example) and adds a `feeds.yml` editor under Features. Each entry is a collection query — the same fields you write in a `collection` block — plus a title:

```yaml
articles:
  title: "Articles"
  description: "Long-form pieces"
  source: posts
  post_type: article
  order: date
  limit: 20
  audience: free

music:
  title: "Music"
  source: posts
  tags: music
```

Each feed is served at two URLs, using its key from the file:

| Format | URL |
|--------|-----|
| RSS 2.0 | `/feed/<name>.xml` |
| Atom | `/feed/<name>.atom` |

So the `articles` feed above is at `/feed/articles.xml`.

### Fields

| Field | Purpose |
|-------|---------|
| `title` | The feed’s channel title (defaults to the site title) |
| `description` | The feed’s channel description |
| `source` | Where items come from: `posts` (default), `pages`, `documentation`, `products` |
| `post_type` | Limit posts to one type, e.g. `article` |
| `tags` | Include by tag; prefix with `-` to exclude, e.g. `music, -draft` |
| `order` | `date` (default), `date-asc`, `title`, or an explicit list of `url_name`s |
| `limit` | How many items to include (default 20) |
| `audience` | `free` (default) or `paid` |

### Free and paid feeds

A **free** feed is public and never includes paid content, even if your site shows paid teasers on the page. A **paid** feed is private: it includes everything, but a reader must supply a paid member’s access token (the same token that unlocks a private podcast feed), so it’s only served to paying members. If you build a static site, free feeds are written out as files; paid feeds are not, since a static file couldn’t enforce the token.

Named feeds are for standard content. A podcast needs its own feed with enclosures and iTunes tags — see below.

## Podcast Feeds

Podcast episodes have their own dedicated RSS feeds with full iTunes/Apple Podcasts support. These are separate from the main blog feed.

See [Podcast Feeds & Tags](/documentation/roe/podcast-feed-tags) for full details on podcast feed URLs, paid/private feeds, and the iTunes tags Roe generates.

## Music Release Feeds

Music releases can be published as podcast feeds so people can add them to their podcast players. They can be paid/private just like the Podcasts feature so only paying members can access the release.

## Auto-Discovery

Roe injects `<link rel="alternate">` tags into every public page’s `<head>` so feed readers can auto-discover your feeds. Podcast episode pages also include a feed discovery link pointing at that podcast’s RSS feed.

## Notes

- The RSS feed uses `pubDate` (RFC 822 format); the Atom feed uses `updated` (ISO 8601).
- Card blocks and collection blocks are stripped from post content before generating feed descriptions.
- Paid posts (audience: paid) are not included in the public blog feed. They appear in podcast feeds only when a member accesses their private feed URL.

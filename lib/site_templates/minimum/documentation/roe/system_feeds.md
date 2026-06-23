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
source: documentation
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

## Podcast Feeds

Podcast episodes have their own dedicated RSS feeds with full iTunes/Apple Podcasts support. These are separate from the main blog feed.

See [Podcast Feeds & Tags](/documentation/podcast-feed-tags) for full details on podcast feed URLs, paid/private feeds, and the iTunes tags Roe generates.

## Auto-Discovery

Roe injects `<link rel="alternate">` tags into every public page’s `<head>` so feed readers can auto-discover your feeds. Podcast episode pages also include a feed discovery link pointing at that podcast’s RSS feed.

## Notes

- The RSS feed uses `pubDate` (RFC 822 format); the Atom feed uses `updated` (ISO 8601).
- Card blocks and collection blocks are stripped from post content before generating feed descriptions.
- Paid posts (audience: paid) are not included in the public blog feed. They appear in podcast feeds only when a member accesses their private feed URL.

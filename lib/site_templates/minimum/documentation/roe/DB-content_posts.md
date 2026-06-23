---
title: Posts
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

# Posts

A Roe site is mostly [Markdown](/documentation/glossary#markdown) and [YAML](/documentation/glossary#yaml) files. There are 4 sources of content in Roe: [Pages](/documentation/pages), Posts, [Products](/documentation/products) (if you've enabled the Store) and Documentation.

Your Post files are in the `/site/posts` folder in your `Roe` folder (where you've installed Roe).

## Products in Roe

Posts are dated content that appears in feeds and collections. They're the primary content type for:

- Blog articles
- Podcast episodes
- Video posts
- Audio/music posts
- Newsletters

Posts are ordered by date (newest first by default) and appear in your RSS/Atom feeds automatically.

## Post Types

Set the `post_type` in your metadata to control how a post is displayed:

| Type | Use For |
|------|---------|
| `article` | Standard blog posts (default) |
| `podcast` | Podcast episodes with audio player and feed support |
| `audio` | Music or audio posts |
| `video` | Video posts with player |

Changing the post type in the editor reveals different metadata fields. For example, `podcast` shows episode number, duration, and audio file fields.

## Creating Posts

Create a new post in [Admin → Posts](/admin/posts) or add a `.md` file to `/site/posts`.

### Required Metadata

```yaml
---
title: My First Post
date: 2026-06-22
status: published
---
```

### Post-Specific Metadata

| Field | Description |
|-------|-------------|
| `date` | Publish date in `YYYY-MM-DD` format. Controls sort order. |
| `post_type` | `article`, `podcast`, `audio`, or `video` |
| `author` | Post author (defaults to site author if not set) |
| `podcast` | Which podcast feed this belongs to (for podcast episodes) |
| `audio` | Audio file path (for podcast/audio posts) |
| `duration` | Audio/video duration (auto-extracted when possible) |

### Publishing Options

When [Newsletters](/documentation/newsletters) are enabled, posts get a `published_to` field:

| Option | Behavior |
|--------|----------|
| `site` | Publish to site only (default) |
| `newsletter` | Send as email only |
| `both` | Publish to site AND send as newsletter |

### Audience

When [Members](/documentation/members) are enabled, posts get an `audience` field:

| Option | Behavior |
|--------|----------|
| `everyone` | Visible to all visitors (default) |
| `paid` | Only visible to paid members |

<mark>Note:</mark> You can decide if you want paid content to show up in feeds and Collections. You can turn on paid content for everyone here: [Admin → Settings → Members](/admin/configs/members/edit) and they'll see a paid-lock-icon next to paid posts.

## Post URLs

Posts get URLs automatically from their title:

```
/posts/my-first-post
```

Override with `url_name`:

```yaml
url_name: custom-post-slug
```

## Collections

Posts are the default source for [Collections](/documentation/collections). You can filter collections by:

- `post_type` — show only podcasts, articles, etc.
- `tags` — filter by tags
- `podcast` — filter by podcast feed
- `related` — show bidirectionally related posts

## Editing Posts

Use [The Editor](/documentation/the-editor) to write post content. The editor shows different metadata fields depending on your post type.

### Common Workflow

1. Create a draft post
2. Write content using Markdown and [Roeanji](/documentation/roeanji) features
3. Preview with `cmd/ctrl-p`
    - Open this window/tab side-by-side to see the live preview as you save.
4. Set `status: published` when ready
5. If newsletters are enabled, choose `published_to: both` to email subscribers

## Podcast Episodes

Podcast episodes are posts with `post_type: podcast`. See [Podcasts](/documentation/podcasts) for full details on creating and managing podcast feeds.

## Audio & Video Posts

Non-podcast audio and video posts use `post_type: audio` or `post_type: video`. These include media players on the post page but don't appear in podcast RSS feeds.

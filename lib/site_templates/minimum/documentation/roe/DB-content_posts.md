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

A Roe site is mostly [Markdown](/documentation/roe/glossary#markdown) and [YAML](/documentation/roe/glossary#yaml) files. There are 4 sources of content in Roe: [Pages](/documentation/roe/pages), Posts, [Products](/documentation/roe/products) (if you've enabled the Store) and Documentation.

Your Post files are in the `/site/posts` folder in your `Roe` folder (where you've installed Roe).

## Products in Roe

Posts are dated content that appears in feeds and collections. They're the primary content type for:

- Blog posts & Newsletters
- Podcast episodes
- Music tracks
- Video or audio posts

Posts are ordered by date (newest first by default) and appear in your RSS/Atom feeds automatically.

## Post Types

Set the `post_type` in your metadata to control how a post is displayed:

| Type | Use For |
|------|---------|
| `article` | Standard blog posts (default) |
| `podcast` | Podcast episodes with audio player and feed support |
| `music` | Tracks, grouped into releases — see [Settings → Music](/documentation/roe/settings-music) |
| `audio` | Non-podcast audio posts |
| `video` | Video posts with player |

Changing the post type in the editor reveals different metadata fields. For example, `podcast` shows episode number, duration, and audio file fields.

## Creating Posts

Create a new post in [Admin → Posts](/admin/posts) or add any markdown file (`.md`) to your `site/posts` folder in the Roe folder.

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
| `post_type` | `article`, `podcast`, `music`, `audio`, or `video` |
| `author` | Post author (defaults to site author if not set) |
| `podcast` | Which podcast feed this belongs to (for podcast episodes) |
| `audio` | Audio file path (for podcast/audio posts) |
| `duration` | Audio/video duration (auto-extracted when possible) |

### Publishing Options

When [Newsletters](/documentation/roe/newsletters) are enabled, posts get a `published_to` field:

| Option | Behavior |
|--------|----------|
| `site` | Publish to site only (default) |
| `newsletter` | Send as email only |
| `both` | Publish to site AND send as newsletter |

### Audience

When [Members](/documentation/roe/members) are enabled, posts get an `audience` field:

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

Posts are the default source for [Collections](/documentation/roe/collections). You can filter collections by:

- `post_type` — show only podcasts, articles, etc.
- `tags` — filter by tags
- `podcast` — filter by podcast feed
- `related` — show bidirectionally related posts

## Editing Posts

Use [The Editor](/documentation/roe/the-editor) to write post content. The editor shows different metadata fields depending on your post type.

### Common Workflow

1. Create a draft post
2. Write content using Markdown and [Roe-anji](/documentation/roe/roeanji) features
3. Preview with `cmd/ctrl-p`
    - Open this window/tab side-by-side to see the live preview as you save.
4. Set `status: published` when ready
5. If newsletters are enabled, choose `published_to: both` to email subscribers

## Podcast Episodes

Podcast episodes are posts with `post_type: podcast`. See [Podcasts](/documentation/roe/podcasts) for full details on creating and managing podcast feeds.

## Music

<mark>Music only:</mark> `post_type: music` needs the **Music** feature turned on. Until then it won't appear in the post-type list. Enable the music feature at [Admin → Settings](/admin/configs) — see [Settings → Music](/documentation/roe/settings-music).

A music post is a track. Alongside the usual fields it takes:

- `audio` — the track itself
- `release` — which release it belongs to, defaults to "singles"
- `track_number` — its place on that release
- `duration` — filled in from the audio file

You don't have to set up a release first. Roe seeds one called `singles`, and new music posts use it unless you choose otherwise, so a one-off track works straight away.

A track with no `image` of its own uses the cover are from the release in the player. [Settings → Music](/documentation/roe/settings-music) covers defining releases and what each one can set.

### Credits and codes

These live with the track, because they describe this recording:

| Field | What it's for |
|-------|---------------|
| `explicit` | `true` or `false`. Marks the track, and its release's feed, as explicit |
| `isrc` | The recording's code, e.g. `QMZ123456789` |
| `songwriters` | Legal names, comma-separated — not stage names |
| `lyrics` | The full text |

`isrc`, `songwriters` and `lyrics` are stored with the track and not yet shown anywhere. Fill them in if you want the record kept alongside the music; nothing depends on them.

Switching a post to `post_type: music` adds these fields to the editor.

### Showing a release

Use a [collection](/documentation/roe/collections) filtered by `release:`, and order it by `track_number` to get the running order. The [`playlist` template](/documentation/roe/collections_templates#when-to-use-the-playlist-template) lays those out as a track list with a player at the top.

Roe warns you in the editor if a track number is already taken within the same release, so two tracks don't end up sharing the same position.

A release can also be published as a podcast feed, which is a tick box in [Settings → Music](/documentation/roe/settings-music#releasing-music-as-a-podcast-feed). Tracks will appear in the order of the `track_numbers` for each track.

## Audio & Video Posts

Non-podcast audio and video posts use `post_type: audio` or `post_type: video`. These include media players on the post page but don't appear in podcast RSS feeds.

---
title: Podcasts
tags: feature
status: published
---

# Podcasts

## Global Settings

To create a podcast, go to the Settings page and click the `ADD PODCAST` button. This will generate the settings file (`podcast.yml`) and edit it.

These are the global settings for your podcast and all should be filled in. A breakdown of these settings and what they represent can be found here: [Podcast Feed & Tags](/documentation/roe/podcast-feed-tags).

## Episode

To create a podcast episode:

1. create a new post
2. change the `post_type` to `podcast`
3. fill in all the required fields.

<mark>Note: Podcasts must have a:</mark> `GUID`. This is a global unique identifier for each episode. This is what allows you to change info about an episode after it's been published and not cause mayhem. All the podcast directories and apps look for this `GUID` to identify the episode. Roe will do it's very best to not allow you to delete or change the `GUID`. It is added to the post metadata automatically when you publish an episode and will be re-added if it is ever deleted or changed.

## Podcast Fields

Every podcast episode is a post with `post_type: podcast`. Below is the full list of fields the editor recognizes, grouped by importance.

### Required

Without these, the post won't publish.

| Field | Type | Notes |
|-------|------|-------|
| `title` | text | Episode title. |
| `date` | datetime | Publish date. |
| `status` | select | `draft`, `published`, or `unlisted`. |
| `post_type` | select | Set to `podcast`. |
| `audio` | text | Audio file path, e.g. `/media/audio/episode-1.mp3`. |
| `duration` | text | Auto-extracted from the audio file when possible. Manual entry accepts seconds (`3600`) or HH:MM:SS (`01:00:00`). |

### Conditionally Required

Required only when the corresponding feature is on.

| Field | When required | Type | Notes |
|---|---|---|---|
| `audience` | Memberships enabled | select | `everyone` or `paid`. |
| `published_to` | Newsletters enabled | select | `site`, `newsletter`, or `both`. |

### Recommended

You can skip these, but the episode will be missing something common.

| Field | Type | Notes |
|---|---|---|
| `podcast` | select | Which podcast feed this episode belongs to. Leave blank for a local-only episode that won't appear in any RSS feed. |
| `episode_number` | text | Episode number, e.g. `1`. |
| `subtitle` | text | Short episode description. Shown in podcast directories. |

### Optional

Everything else the editor surfaces for podcast posts.

| Field | Type | Notes |
|-------|------|-------|
| `excerpt` | textarea | Longer excerpt. |
| `season` | text | Season number, e.g. `1`. |
| `episode_type` | select | `full`, `trailer`, or `bonus`. |
| `explicit` | select | `true` or `false`. |
| `author` | text | Overrides the podcast's default author for this episode. |
| `image` | text | Episode artwork override, e.g. `/media/images/episode-1.jpg`. |
| `video` | text | Adds a video version. The site plays video when present; the RSS feed still uses the audio file. |
| `captions` | text | VTT captions/transcript path, e.g. `/media/captions/episode-1.en.vtt`. |
| `tags` | text | Comma-separated tags. |
| `url_name` | text | Auto-generated from title if blank. |
| `show_sidebar` | select | `true` or `false`. |
| `image_in_header` | select | `true` or `false`. |

### Auto-managed

You don't write these yourself; Roe sets and maintains them.

| Field | Type | Notes |
|---|---|---|
| `guid` | text | Auto-generated UUID, locked once published — podcast clients depend on stability. When importing from another platform (Substack etc.), the original GUID is preserved verbatim so existing subscribers don't see every episode as new. |

## Subscribe Section

Every podcast episode page shows a **subscribe section** — links to your show on the podcast apps, plus the RSS feed. You can also place it on an ordinary page (see [Podcast Pages](#podcast-pages) below).

### App / service links (podcast.yml)

Each podcast block in `podcast.yml` carries a set of subscribe-link fields. Paste your show's page URL on each platform; leave any blank to hide it. They appear in the podcast settings editor.

| Field | Platform |
|---|---|
| `apple_podcasts` | Apple Podcasts |
| `spotify` | Spotify |
| `youtube` | YouTube |
| `overcast` | Overcast |
| `pocket_casts` | Pocket Casts |
| `amazon_music` | Amazon Music |

Use the normal `https://` share link for your show on each service (each app's **Share → Copy Link**) — those open the native app when it's installed and fall back to the browser otherwise. Don't use `overcast://`-style deep links; they break on desktop and where the app isn't installed.

The **RSS feed is added automatically** (you don't put a feed URL in these fields), and for paid shows a **private feed link** appears for admins and for paid, active members.

### Display: all links, or a Subscribe button

| Field | Options |
|---|---|
| `subscribe_display` | `links` (default) shows every link inline; `menu` collapses them behind a single **Subscribe** button |

## Podcast Pages

Connect an ordinary page to a show by adding `podcast: <podcast-key>` to its frontmatter — the key is the top-level name in `podcast.yml`, the same value episodes use in their `podcast` field. When the podcast feature is on and the key resolves, the page:

- leads with the **show's name as its heading** (ordinary pages leave the title to the markdown — a podcast page is the exception), and
- shows the **subscribe section** directly beneath it.

This is how you build a "podcast home" landing page; the rest of the page is your normal markdown content.

## Podcast Settings Breakdown

```bash
┌─────────────────────────────────┐
│  Podcast Settings               │
│  (podcast.yml)                  │
└────────────┬────────────────────┘
             │
             │ defaults flow down
             ↓
┌─────────────────────────────────┐
│  Episode Post                   │
│  (Post metadata)                │
│                                 │
│  • Can override defaults        │
└────────────┬────────────────────┘
             │
             │ combined data
             ↓
┌─────────────────────────────────┐
│  Podcast Feed                   │
│  (Generated RSS/XML)            │
│                                 │
│  Final feed with all tags       │
│  Ready for Apple/Spotify        │
└─────────────────────────────────┘
```

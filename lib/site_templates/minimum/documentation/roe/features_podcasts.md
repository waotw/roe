---
title: Podcasts
tags: feature
status: published
---

# Podcasts

## Global Settings

To create a podcast, go to the Settings page and click the `ADD PODCAST` button. This will generate the settings file (`podcast.yml`) and edit it.

These are the global settings for your podcast and all should be filled in. A breakdown of these settings and what they represent can be found here: [Podcast Feed & Tags](/documentation/roe/podcast-feed-tags).

<mark>Note:</mark> A Podcast can be set to `audience: paid` globally. Any episode connected to that Podcast will also be `paid` unless the post itself sets that episode to `audience: everyone`. This allows you to have some `paid` and some free episodes in your Podcast feed. See [Paid podcasts and releases](/documentation/roe/paid-content#paid-podcasts-and-releases).

## Episode

To create a podcast episode:

1. create a new post
2. change the `post_type` to `podcast`
3. fill in all the required fields.

<mark>Note: Podcasts must have a:</mark> `GUID`. This is a global unique identifier for each episode. This is what allows you to change info about an episode after it's been published and not cause mayhem. All the podcast directories and apps look for this `GUID` to identify the episode. Roe will do it's very best to not allow you to delete or change the `GUID`. It is added to the post metadata automatically when you publish an episode and will be re-added if it is ever deleted or changed.

## Podcast Properties (fields)

Every podcast episode is a post with `post_type: podcast`. Below is the full list of properties the editor recognizes.

### Required

Without these, the post won't publish.

| Property | Description |
|-------|------|-------|
| `title` | Episode title. |
| `date` | Publish date. |
| `status` | `draft`, `published`, or `unlisted`. |
| `post_type` | Set to `podcast`. |
| `audio` | Audio file path, e.g. `/media/audio/episode-1.mp3`. |
| `duration` | Auto-extracted from the audio file when possible. Manual entry accepts seconds (`3600`) or HH:MM:SS (`01:00:00`). |

### Conditionally Required

Required only when a specific feature in Roe is enabled.

| Property | Required by | Description |
|---|---|---|---|
| `audience` | Memberships | `everyone` or `paid`. |
| `published_to` | Newsletters | `site`, `newsletter`, or `both`. |

### Recommended

You can skip these, but the episode will be missing something common.

| Property | Description |
|---|---|---|
| `podcast` | Which podcast feed this episode belongs to. Leave blank for a local-only episode that won't appear in any RSS feed. |
| `episode_number` | Episode number, e.g. `1`. |
| `subtitle` | Short episode description. Shown in podcast directories. |

### Optional

Everything else the editor surfaces for podcast posts.

| Property | Description |
|-------|------|-------|
| `excerpt` | Longer excerpt. |
| `season` | Season number, e.g. `1`. |
| `episode_type` | `full`, `trailer`, or `bonus`. |
| `explicit` | `true` or `false`. |
| `author` | Overrides the podcast's default author for this episode. |
| `image` | Episode artwork override, e.g. `/media/images/episode-1.jpg`. |
| `video` | Adds a video version. The site plays video when present; the RSS feed still uses the audio file. |
| `captions` | VTT captions/transcript path, e.g. `/media/captions/episode-1.en.vtt`. |
| `tags` | Comma-separated tags. |
| `url_name` | Auto-generated from title if blank. |
| `show_sidebar` | `true` or `false`. |
| `image_in_header` | `true` or `false`. |

### Auto-managed

You don't write these yourself; Roe sets and maintains them.

| Property | Description |
|---|---|---|
| `guid` | Auto-generated UUID, locked once published — podcast clients depend on stability. When importing from another platform (Substack etc.), the original GUID is preserved verbatim so existing subscribers don't see every episode as new. |

## Subscribe Section

Every podcast episode page shows a **subscribe section** — links to your show on the podcast apps, plus the RSS feed. You can also place it on an ordinary page (see [Podcast Pages](#podcast-pages) below).

### App / service links (podcast.yml)

Each podcast in Settings → Roe → [Podcasts](/admin/configs/podcast/edit) has a set of subscribe-link properties. Paste your show's page URL on each platform to show those links on the Podcast and episode pages.

| Property | Description
|---|---|
| `apple_podcasts` | URL for your podcast on Apple Podcasts |
| `spotify` | URL for your podcast on Spotify |
| `youtube` | URL for your podcast on YouTube |
| `overcast` | URL for your podcast on Overcast |
| `pocket_casts` | URL for your podcast on Pocket Casts |
| `amazon_music` | URL for your podcast on Amazon Music |

Use the `Share → Copy Link` flow for each platform to get your podcast's URL. Avoid using app specific links such as `overcast://` or `pocketcasts://` and use the web URL (`https://`).

### RSS Feeds

Roe automatically adds RSS feeds for all podcasts to their pages/episodes. More deails here: [Podcast Feeds & Tags](/documentation/roe/podcast-feed-tags)

### Display: all links, or a Subscribe button

| Property | Options |
|---|---|
| `subscribe_display` | `links` (default) shows every link inline<br>`menu` collapses them behind a single **Subscribe** button |

## Podcast Pages

You can connect a podcast to a page by adding `podcast: <podcast-key>` to the metadata for that page — this is the same way you connect a podcast post to its podcast. Podcast pages will have these elements added to them:

- Title of podcast
- Subscribe section with links and RSS feeds

This allows you to create a "home page" for the podcast.

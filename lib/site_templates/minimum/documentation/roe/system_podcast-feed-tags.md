---
title: Podcast Feed & Tags
status: published
tags: system
related:
  - podcasts
  - system-feeds
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Podcast Feeds & Tags

Roe generates a standards-compliant podcast RSS feed for each podcast you configure. These feeds work with Apple Podcasts, Spotify, Overcast, Pocket Casts, and any other podcast app that supports the iTunes namespace.

## Feed URLs

Each podcast gets two feed URLs, derived from the podcast’s key (set in [Admin → Settings → Podcasts](/admin/configs/podcast/edit)):

| Feed | URL | Who can access it |
|------|-----|-------------------|
| Public feed | `/podcast/{podcast-key}.xml` | Everyone |
| Private feed | `/podcast/{podcast-key}/private.xml?token={member-token}` | Paid members only |

### Public Feed

Contains all published episodes with `audience: everyone`. If **Show Paid Content** is enabled in your [Members settings](/admin/configs/members/edit), paid episodes are included as teasers — title and description are shown but the audio enclosure is omitted, and a “subscribers only” note is added to the description.

### Private Feed

Contains all episodes, including paid ones with full audio enclosures. Each paid member gets a unique private feed URL using their personal `access_token`. Members can find their private feed URL on their account page.

Admins can access the private feed directly without a token.

<mark>Note:</mark> If a podcast’s `audience` is set to `paid` in podcast.yml, no public feed exists at all — only the private feed.

### Music Release Feed

A music release published as a feed gets the same two URLs a podcast does, derived from the release key:

| Feed | URL | Who can access it |
|------|-----|-------------------|
| Public feed | `/music/{release-key}.xml` | Everyone |
| Private feed | `/music/{release-key}/private.xml?token={member-token}` | Paid members only |

It's the same RSS format, built from the release rather than from `podcast.yml`, so the tags below apply — with the differences noted in [Release Feed Differences](#release-feed-differences).

Paid tracks behave exactly as paid episodes do. The public feed omits their audio, or shows them as teasers when **Show Paid Content** is on; the private feed carries every track with full audio. Paid, active members get their link on a track's page, and admins can open the private feed without a token.

<mark>Note:</mark> If a release's `audience` is `paid`, no public feed exists at all — only the private feed. Turning the feed off removes both.

---

## Channel-Level (Podcast Configuration)

### Required

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `title` | `title` | Podcast name |
| `link` | `link` | Podcast website URL |
| `description` | `description` | Podcast description |
| `language` | `language` | Language code (e.g., "en") |
| `itunes:author` | `author` | Show creator/host |
| `itunes:image` | `artwork` | Artwork (1400x1400 to 3000x3000 px, JPG/PNG) |
| `itunes:category` | `category` | At least one iTunes category |
| `itunes:explicit` | `explicit` | true/false |
| `itunes:owner` | `owner_name` (or `author`) + `email` | Contact name and email. Uses `owner_name` if set, otherwise falls back to `author`. |

### Recommended

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `itunes:type` | `type` | "episodic" or "serial" |
| `copyright` | `copyright` | Copyright notice |
| `itunes:summary` | `description` | Longer description (same as description) |

### Situational

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `itunes:category` | `category_secondary` | Secondary category |
| subcategories | `subcategory`, `subcategory_secondary` | Up to 2 subcategories per category (where available in iTunes taxonomy) |

<mark>Note:</mark> `podcast.yml` also holds **subscribe-link** fields (`apple_podcasts`, `spotify`, `youtube`, `overcast`, `pocket_casts`, `amazon_music`) and `subscribe_display`. These drive the on-site [subscribe section](/documentation/podcasts#subscribe-section) — they are **not** feed tags and appear nowhere in the RSS/XML.

---

## Item-Level (Episode Metadata)

### Required

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `title` | `title` | Episode title |
| `enclosure` | `audio` | Audio file path |
| `guid` | `guid` | Permanent unique ID (auto-generated) |
| `pubDate` | `date` | Publication date |

### Recommended

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `description` | `content` | Show notes (HTML supported) |
| `itunes:summary` | `excerpt` → `subtitle` → first sentence | Plain text summary. Resolved in that order; markdown is stripped. |
| `itunes:duration` | `duration` | Episode length (HH:MM:SS or seconds) |
| `itunes:image` | `image` | Episode-specific artwork |
| `itunes:explicit` | `explicit` | true/false |
| `itunes:episodeType` | `episode_type` | "full", "trailer", or "bonus" |

### Situational

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `itunes:episode` | `episode_number` | Episode number (for episodic shows) |
| `itunes:season` | `season` | Season number (for seasonal shows) |
| `itunes:subtitle` | `subtitle` | Short teaser/tagline |
| `itunes:author` | `author` | Override podcast default author |

---

## Release Feed Differences

A [music release feed](/documentation/roe/settings-music#releasing-music-as-a-podcast-feed) uses the same format, filled in from the release and its tracks instead of from `podcast.yml`. What differs:

| Tag | Where it comes from | Note |
|:----|:--------------------|:-----|
| `itunes:category` | Always `Music` | Apple validates categories against a fixed list, so a release's `genre` can't be used here |
| `itunes:type` | Always `serial` | Players start at track one instead of the newest track |
| `itunes:episode` | `track_number` | A track's place in the running order |
| `itunes:explicit` | Any track's `explicit` | One explicit track marks the whole release |
| `itunes:author`, `itunes:owner` | The release's artist | Falls back to the default artist, then your site author |
| `itunes:image` | The release's `cover` | |
| `description` | The release's `synopsis` | |
| `itunes:owner` email | `author_email` in [site.yml](/admin/configs/site/edit) | Apple emails it to verify you own the feed |

Two tags appear only in a release feed:

| Tag | Value | Why |
|:----|:------|:----|
| `podcast:medium` | `music` | Tells apps that read the Podcasting 2.0 namespace to treat the feed as music rather than as a show |
| `category` | The release's `genre` | Plain RSS, not iTunes. Carries the genre where it can't cause a rejection |

Both are additive and sit in territory Apple and Spotify ignore, so they don't affect distribution. Neither appears in a podcast feed.

Tracks are sorted by `track_number`, with unnumbered tracks last. Only published tracks on that release are included.

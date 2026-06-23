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

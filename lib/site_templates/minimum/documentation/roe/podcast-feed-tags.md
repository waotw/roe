---
roe_version: 0.0.20
title: Podcast Feed & Tags
status: unlisted
--- 

# Podcast Feed & Tags
[← Back to Podcasts](/documentation/podcasts)

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
| `itunes:owner` | `author` + `email` | Contact name and email |

### Recommended

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `itunes:type` | `type` | "episodic" or "serial" |
| `copyright` | `copyright` | Copyright notice |
| `itunes:summary` | `description` | Longer description (same as description) |

### Situational

| iTunes Tag | Roe Field | Description |
|:-----------|:----------|:------------|
| `itunes:category` | `category_2` | Secondary category (up to 3 total) |
| subcategories | `subcategory`, `subcategory_2` | Up to 2 per category (if available) |

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
| `itunes:summary` | `excerpt` or `subtitle` | Plain text summary |
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

# Podcasts

Roe provides first-class podcast support with RSS feed generation, per-episode artwork, duration extraction, and optional private feeds for paid members.

## Architecture Overview

```
Podcast Post
      │
      ▼
┌─────────────────────────────────────┐
│   PodcastConfig                     │
│   (site/system/features/podcast.yml)│
│                                     │
│  • Title, description, artwork      │
│  • RSS feed settings                │
│  • Private feed tokens              │
└──────────────┬──────────────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
┌──────────┐     ┌──────────────┐
│  Public  │     │   Private    │
│  Feed    │     │   Feed       │
│          │     │              │
│/podcast/ │     │/podcast/:key/│
│feed.xml  │     │private.xml   │
└──────────┘     └──────────────┘
```

**Graph Note:** Podcast functionality spans multiple communities including Feed Generation, Content Management, and Member Authentication (37 edges from Converter + FeedGenerator).

## Podcast Configuration

File: `app/models/podcast_config.rb`

### Configuration File

`podcast.yml` is a map of **podcast key → config**. Even a single show is keyed — the key becomes the feed URL slug (`/podcast/<key>.xml`) and the value episodes reference in their `podcast:` field.

```yaml
# site/system/features/podcast.yml
my-podcast:
  title: "My Podcast"
  description: "A podcast about..."
  author: "Your Name"
  email: "podcast@example.com"
  owner_name: "Your Name"
  category: "Technology"
  subcategory: "Software How-To"
  language: "en"
  copyright: "2026 Your Name"
  explicit: false
  type: "episodic"          # episodic | serial
  artwork: "podcast-artwork.jpg"
  link: "https://example.com"

  # Paid gating (surfaced when Members is enabled)
  audience: ""              # "" / everyone, or "paid" for a paid-only show

  # Subscribe links (blank = hidden; the RSS feed is added automatically)
  apple_podcasts: ""
  spotify: ""
  youtube: ""
  overcast: ""
  pocket_casts: ""
  amazon_music: ""
  subscribe_display: "links"  # links | menu
```

The iTunes-spec metadata set lives in `PodcastConfig::CANONICAL_FIELDS`; `PodcastConfig::SUBSCRIBE_APPS` / `SUBSCRIBE_FIELDS` hold the subscribe-link fields. `audience` and the subscribe fields are auto-surfaced in the admin editor via backfill (they aren't part of the iTunes canonical set and never appear in the feed XML).

### Multiple Podcasts

Add more top-level keys — one per show. `PodcastConfig.get(key)` resolves a block, and a `parent:` key merges a parent's fields for series/spin-offs:

```yaml
# site/system/features/podcast.yml
main:
  title: "Main Podcast"
  # ...
bonus:
  parent: main              # inherits main's fields; override as needed
  title: "Bonus Episodes"
```

## Creating Podcast Posts

### Frontmatter

```markdown
---
title: "Episode 1: Getting Started"
date: 2024-01-15
post_type: podcast
podcast: main
audio: media/audio/episode-1.mp3
duration: 3600  # Seconds (auto-extracted if not specified)
guid: "episode-001"  # Unique identifier
episode_number: 1
season_number: 1
artwork: media/images/episode-1-artwork.jpg
explicit: false
---

Episode content in Markdown...
```

### Audio File Location

Place audio files in `site/media/audio/`:

```
site/media/audio/
├── episode-1.mp3
├── episode-2.mp3
└── bonus-content.mp3
```

### Duration Extraction

Roe automatically extracts duration from MP3 files:

```ruby
# app/services/media_duration_extractor.rb
MediaDurationExtractor.call(file_path)  # Returns seconds
```

If extraction fails, you must provide `duration:` in frontmatter.

## RSS Feed Generation

File: `app/services/feed_generator.rb`

### Public Feed

```
GET /podcast/:podcast_key/feed.xml
```

Returns RSS 2.0 with iTunes extensions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>My Podcast</title>
    <description>A podcast about...</description>
    <itunes:author>Your Name</itunes:author>
    <itunes:image href="https://.../artwork.jpg"/>
    <item>
      <title>Episode 1: Getting Started</title>
      <enclosure url="https://.../episode-1.mp3" length="12345678" type="audio/mpeg"/>
      <itunes:duration>3600</itunes:duration>
      <guid isPermaLink="false">episode-001</guid>
    </item>
  </channel>
</rss>
```

### Private Feeds (Paid Members)

Enable private feeds for paid content:

```
GET /podcast/:podcast_key/private.xml?token=member_token
```

**Token-based authentication:**
- Each paid member gets a unique token
- Token is in their account page
- Feed includes all episodes (public + paid)

```ruby
# FeedsController#private_podcast
def private_podcast
  member = Member.find_by(private_feed_token: params[:token])
  
  unless member&.paid?
    head :unauthorized
    return
  end
  
  render_feed(include_paid: true)
end
```

### Feed Validation

Submit feeds to podcast directories:

- **Apple Podcasts:** https://podcastsconnect.apple.com
- **Spotify:** https://podcasters.spotify.com
- **Google Podcasts:** https://podcasts.google.com/submit

## Import from RSS

File: `app/services/podcast_feed_fetcher.rb`, `app/services/podcast_feed_parser.rb`

### Auto-Seed from Existing Feed

Import podcast metadata and episodes from an existing RSS feed:

1. Go to **Admin → Config → Podcast**
2. Click "Seed from RSS Feed"
3. Enter RSS URL (e.g., Substack feed)
4. Roe imports:
   - Podcast metadata (title, description, artwork)
   - Episode data (title, audio URL, duration, GUIDs)
   - Creates local posts for each episode

### Import Process

```ruby
# PodcastFeedFetcher.fetch(url)
def fetch(url)
  response = HTTParty.get(url, timeout: 30)
  PodcastFeedParser.parse(response.body)
end
```

### GUID Handling

GUIDs (Globally Unique Identifiers) are preserved during import:

- **Public episodes:** Keep original GUID
- **Private episodes:** Append suffix to avoid conflicts
- **Local-only episodes:** Generate new GUID if not provided

```ruby
# In publish modal for imported episodes
guid_field(:read_only) if episode.imported?
```

## Podcast Post Type

### Rendering

Podcast posts render with:
- Audio player (HTML5 `<audio>`)
- Episode artwork (or podcast default)
- Show notes (Markdown content)
- Subscribe section — app/service links + public RSS + (for admins / paid, active members) the private feed

```erb
<%# app/views/posts/types/_podcast.html.erb %>
<article class="podcast-episode">
  <h1><%= post.title %></h1>
  
  <% if post.artwork %>
    <%= image_tag post.artwork %>
  <% end %>
  
  <audio controls src="<%= post.audio_path %>">
  </audio>
  
  <div class="show-notes">
    <%= post.to_html %>
  </div>
  
  <%= render 'posts/types/podcast_subscribe', post: post, podcast_config: podcast_config %>
</article>
```

The subscribe section is `app/views/posts/types/_podcast_subscribe.html.erb`. `subscribe_display: menu` collapses the links behind a native `<details>` "Subscribe" button (no JS). The same partial renders on any **page** with a `podcast: <key>` frontmatter key — `pages/show.html.erb` leads with the show name as an `<h1>` and renders the subscribe section beneath it (a "podcast home" page).

### Collections

Filter podcast episodes in collections:

```markdown
<!-- Inline collection -->
:collection{source="posts" post_type="podcast" limit="10"}

<!-- Specific podcast -->
:collection{source="posts" podcast="main" limit="5"}
```

## Admin Interface

### Podcast Config Page

**Admin → Config → Podcast:**

- Feed metadata (title, description, artwork)
- Category selection (iTunes categories)
- External links (Apple, Spotify, Google)
- Private feed settings
- "Seed from RSS" button

### Per-Podcast Display

```erb
<%# app/views/admin/configs/_podcast_section.html.erb %>
<h3><%= podcast.title %></h3>

<div class="field">
  <%= label :artwork %>
  <%= media_picker :artwork %>
</div>

<div class="field">
  <%= label :private_feed_enabled %>
  <%= checkbox :private_feed_enabled %>
</div>
```

## Feed XML Structure

### Required Elements

```xml
<channel>
  <!-- Required -->
  <title>Podcast Title</title>
  <description>Podcast description</description>
  <link>https://yoursite.com</link>
  <language>en</language>
  
  <!-- iTunes Required -->
  <itunes:author>Author Name</itunes:author>
  <itunes:category text="Technology"/>
  <itunes:image href="https://.../artwork.jpg"/>
  <itunes:explicit>no</itunes:explicit>
</channel>
```

### Episode Elements

```xml
<item>
  <title>Episode Title</title>
  <description>Episode description</description>
  <pubDate>Mon, 15 Jan 2024 00:00:00 GMT</pubDate>
  <guid isPermaLink="false">unique-id</guid>
  
  <!-- Audio -->
  <enclosure 
    url="https://.../episode.mp3" 
    length="12345678" 
    type="audio/mpeg"/>
  
  <!-- iTunes -->
  <itunes:duration>3600</itunes:duration>
  <itunes:episode>1</itunes:episode>
  <itunes:season>1</itunes:season>
  <itunes:image href="https://.../episode-artwork.jpg"/>
</item>
```

## Static Generation

Podcast feeds are pre-generated during static build:

```ruby
# StaticGenerator
def generate_podcast_feeds
  PodcastConfig.all.each do |podcast|
    xml = FeedGenerator.generate_podcast_feed(podcast)
    write_to_output("/podcast/#{podcast.key}/feed.xml", xml)
  end
end
```

## Troubleshooting

### Feed not validating

**Check:**
- All required iTunes elements present
- Artwork is square (1400x1400 to 3000x3000)
- Audio URLs are publicly accessible
- Duration format is HH:MM:SS or seconds

### Private feed 401 errors

**Check:**
- Member has active subscription
- Token hasn't expired
- URL includes `?token=` parameter

### Episodes not appearing

**Check:**
- Post has `post_type: podcast`
- `audio:` field points to valid file
- Post status is `published`
- Audio file exists in `site/media/audio/`

### Duration showing as 0:00

**Fix:**
- Extract manually: `ffprobe -i file.mp3 -show_entries format=duration -v quiet`
- Add `duration: 3600` to frontmatter

## Related

- [Content System](./02-content-system.md) - Post types and frontmatter
- [Members & Authentication](./11-members-authentication.md) - Private feed tokens
- [Sync & Generation](./05-sync-generation.md) - Static feed generation
- [Substack Importer](./15-substack-importer.md) - Import existing podcast

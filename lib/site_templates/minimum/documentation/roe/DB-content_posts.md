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

At it's core, a Roe website is just a bunch of text files. There are 4 sources of content in Roe: [Pages](/documentation/roe/pages), Posts, [Products](/documentation/roe/products) (if you've enabled the Store) and Documentation.

Your Post files are in the `/site/posts` folder in your `Roe` folder (where you've installed Roe).

## Posts in Roe

Posts are dated content that appears in feeds and collections. They're the primary content type for:

- Blog posts & Newsletters
- Podcast episodes
- Music tracks
- Video or audio posts

Posts are ordered by date (newest first by default) and appear in your RSS/Atom feeds automatically.

## Post Types

Set the `post_type` in your metadata to control how a post is displayed:

| Type | Description |
|------|---------|
| `article` | Standard blog posts (default) |
| `podcast` | Podcast episodes with audio player and feed support — see [Podcasts](/documentation/roe/podcasts) |
| `music` | Tracks, grouped into releases — see [Music](/documentation/roe/settings-music) |
| `audio` | Non-podcast audio posts |
| `video` | Video posts with player |

Changing the post type in the editor reveals different metadata properties. For example, `podcast` shows `episode_number`, `duration`, and `audio` file properties.

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

| Property | Description |
|-------|-------------|
| `date` | Publish date with time in `2026-08-25T10:31Z` format. Controls sort order. |
| `post_type` | `article`, `podcast`, `music`, `audio`, or `video` |
| `author` | Post author (defaults to site author if not set) |
| `podcast` | Which podcast feed this belongs to (for podcast episodes) |
| `audio` | Audio file path (for podcast/audio posts) |
| `duration` | Audio/video duration (auto-extracted when possible) |

### Publishing Options

When [Newsletters](/documentation/roe/newsletters) are enabled, posts get a `published_to` property:

| Option | Behavior |
|--------|----------|
| `site` | Publish to site only (default) |
| `newsletter` | Send as email only |
| `both` | Publish to site AND send as newsletter |

### Audience

When [Members](/documentation/roe/members) are enabled, posts get an `audience` property:

| Option | Behavior |
|--------|----------|
| `everyone` | Visible to all visitors (default) |
| `paid` | Only visible to paid members |

<mark>Note:</mark> You can decide if you want paid content to show up in feeds and Collections. You can turn on paid content for everyone here: [Admin → Settings → Members](/admin/configs/members/edit) and they'll see a paid-lock-icon next to paid posts.

## Post URLs

Posts get URLs automatically from their title:

```
title: My First Post
/posts/my-first-post
```

Customize with `url_name`:

```yaml
url_name: my-very-first-post
```

## Collections

Posts are the default source for [Collections](/documentation/roe/collections). You can change the default here: [Settings → Collections](/admin/configs/collections/edit) You can filter collections by:

- `post_type` — show only podcasts, articles, etc.
- `tags` — filter by tags
- `podcast` — filter by podcast feed
- `related` — show related posts — see [Show related content](/documentation/roe/collections#show-related-content)

## Editing Posts

Use [The Editor](/documentation/roe/the-editor) to write posts. The editor shows different metadata properties depending on your `post_type`.

### Common Workflow

1. Click `NEW POST` on the [Posts Index Page](/admin/posts)
  - Add `title` and choose a `post_type`.
  - Fill in the properties for that post (you can change these later)
  - Click `CREATE POST` or hit `ENTER/RETURN`.
2. Write content using [Markdown](/documentation/roe/glossary#markdown) and [Roe-anji](/documentation/roe/roeanji) features
3. Preview with the `PREVIEW` button or `cmd/ctrl-p`
    - Open this window/tab side-by-side to see the live preview as you write your post.
4. Set `status: published` when ready
5. If newsletters are enabled, choose `published_to: both` to email subscribers

## Audience on a new post

When Members is on, the `NEW POST` form asks for an `audience`. The default is `everyone`, unless you have a `paid` podcast or release and you choose it — then it defaults to `paid`. Paid podcasts can have free episodes. Set the `audience` to whatever you like.

See [Paid content](/documentation/roe/paid-content) for what `audience` does once it's set.

## Podcast Episodes

Podcast episodes are posts with `post_type: podcast`. See [Podcasts](/documentation/roe/podcasts) for full details on creating and managing podcasts and their feeds.

## Music

Music tracks are posts with `post_type: music`. See [Features → Music](/documentation/roe/settings-music) for full details on creating and managing music in Roe.

A music post is a track. Alongside the usual properties it uses:

- `audio` — the track itself
- `release` — which release it belongs to, defaults to "singles"
- `track_number` — its place on that release
- `duration` — filled in from the audio file

Switching a post to `post_type: music` adds these properties to the editor.

You don't have to set up a release first. Roe creates one called `singles` when you enable the Music feature, so a one-off track works straight away.

A track with no `image` of its own uses the cover are from the release in the player. [Settings → Music](/documentation/roe/settings-music) covers defining releases and what each one can set.

### Credits and codes

These live with the track, because they describe this recording:

| Property | What it's for |
|-------|---------------|
| `explicit` | `true` or `false`. Marks the track, and its release's feed, as explicit |
| `isrc` | The recording's code, e.g. `QMZ123456789` |
| `songwriters` | Legal names, comma-separated — not stage names |
| `lyrics` | The full text |

`isrc`, `songwriters` and `lyrics` are stored with the track and not yet shown anywhere at this time.

### Showing a release

Use a [collection](/documentation/roe/collections) filtered by `release:`, and order it by `track_number` to get the running order. The [`playlist` template](/documentation/roe/collections_templates#when-to-use-the-playlist-template) lays those out as a track list with a player at the top.

A release can also be published as a podcast feed, which is a tick box in [Settings → Music](/documentation/roe/settings-music#releasing-music-as-a-podcast-feed).

## Audio & Video Posts

Non-podcast audio and video posts use `post_type: audio` or `post_type: video`. These include media players on the post page but don't appear in podcast RSS feeds.

---
title: "Music"
status: published
url_name: settings-music
tags: feature
related:
  - posts
  - collections_templates
  - podcasts
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Music: Releases and Settings

The Music feature lets you publish tracks as posts, group them into releases, and — if you want — publish any release as a podcast.

## Turning it on

Go to [Admin → Settings](/admin/configs) and click `Enable Music`. Roe creates `site/system/features/music.yml` and opens the Music settings form.

## You can start posting straight away

Every track belongs to a release, and Roe creates one called `singles` so you can start posting music immediately.

You can create a collection with `template: playlist` and filter it by release: `release: singles`. This will create an audio player with all your singles in it. 

## Adding a release

Click `+ New Release` in [Settings → Music](/admin/configs/music/edit) and fill in the info for this release.

<mark>Note:</mark> The `Release key` is what collections and tracks use to connect to this release. Renaming it later breaks that link on every track that points to this release, and you'd have to update each one by hand. Short and unlikely-to-change beats descriptive.

## What each setting does

| Setting | Description |
|---------|-----------------|
| `title` | The release name. Used as the feed title |
| `artist` | Who it's by. Overrides the default artist for this release |
| `release_date` | When it came out, as `YYYY-MM-DD` |
| `cover` | Cover art. Used by the player and as the feed's artwork |
| `synopsis` | A short description. Used as the feed description |
| `genre` | Free text, e.g. `Shoegaze` |
| `label` | Your label, if you have one |
| `copyright` | ℗ covers the recording, © the song. Usually the same name for both |
| `audience` | `free` or `paid`. Only means anything with [Members](/documentation/roe/members) on |
| `feed` | Publishes this release as a podcast feed — see below |

To make a release, you only need to give it a name. You don't have to fill all of these out.

The two settings at the very top, `artist` and `audience`, will be used for all releases. This can be overridden in the settings for each release.

## How settings are applied from track to release

The most specific settings win:

1. the track
2. the release
3. the settings in Settings → music.yml. If `artist` is not present in the music settings, it will fallback to the site author in Settings → [site.yml](/admin/configs/site/edit).

### How this works in practice:

- **Cover art** — if a track has it's own `image`, that is shown as the artwork for that track. If not, it will use the release's artwork for the player.
- **Artist and audience** — if a track has it's own artist, this is used. If not, it will fallback to the `artist` set in Settings → music.yml.

### An example of how this could be used:

You could create a compilation:

- The `release` could have an `artist` and cover image.
- Each track could have it's own `artist` and `image` (artwork)

## Releasing music as a podcast feed

Tick `Release this as a podcast feed` on a release and Roe publishes an RSS feed at `/music/<release-key>.xml`. Submit that URL to Apple Podcasts, Spotify, or any podcast index/host.

This is separate from the [Podcast feature](/documentation/roe/podcasts). This allows you to release music as a podcast but you don't have to enable Podcasts in Roe to use it.

### What the podcast feed needs

Apple requires several properties when you submit a podcast, Roe can create most of these from the release information but there are 3 it can't create:

- `title` — name of the podcast
- `synopsis` — this becomes the feed's description
- `cover` — square artwork; 3000×3000 JPG or PNG is the standard

These properties are required before Roe will publish the feed.

You also need an author email in [Settings → site](/admin/configs/site/edit). Apple will email that address to confirm you own the feed.

### What Roe fills in for you

| Property | Description |
|---------|-----------------|
| Category | `Music` is always used. Apple validates categories against a fixed list, so a `genre` property can't be used as the category. |
| Track_order | A `music` post's `track_number` is used. The feed is marked as a serial, so players start at track one instead of the newest track. |
| Explicit | This is set on the whole release if any track in it is marked explicit. |
| Copyright | falls back to `℗ & © <year> <artist>` |
| `guid` | A globally unique identifier that is assigned to each track

### The `GUID` property for tracks

Each post with `type: music` has a permanent ID (called a [GUID](/documentation/roe/glossary#guid-globally-unique-identifier)) so podcast apps always know what this track is, even if the title or description changes. Roe writes it when a track is first published and won't let it change — the same protection podcast episodes get. You'll see it as `guid` in the editor, greyed out.

### Paid music

Roe's [Members](/documentation/roe/members) feature allows you to create free and paid music. Paid music is only available to members that have upgraded. When you use this feautre, Roe creates two feeds:

- **The public feed** at `/music/<release-key>.xml` doesn't include "paid" audio files. If you've turned on **Show Paid Content** on in Settings → [Members](/admin/configs/members/edit), paid tracks still appear as teasers — title and description, no audio.
- **The private feed** at `/music/<release-key>/private.xml` carries every track with full audio. Each paid member has their own URL, and it appears on a track's page when they're signed in.

Tracks inherit their release's audience setting. Set `audience: paid` on the release and every track on it is paid, so you don't have to assign an `audience` to every track — and a track that sets its own audience overrides the release, so a paid album can have a free single.

Roe will create a public feed if any of the `music` posts in a release have `audience: everyone` in the post's metadata.

| Release | Tracks | Public feed |
|---------|--------|-------------|
| free | some paid | free tracks, with paid as previews |
| paid | some free | the free tracks |
| paid | none free | no free tracks or public feed |

A paid release with at least one free track will still have a public feed that anyone can subscribe to to get the free tracks and previews of the rest.

Turning the feed off removes all feeds.

## Editing the file directly

`EDIT YAML` let's you edit the file's text directly. You can also edit the file directly in a text editor. Releases live under a `releases:` key:

```yaml
artist: Your Name
audience: free

releases:
  singles:
    title: Singles
    synopsis: Individual tracks, not connected to a release.
  summer-release:
    title: Summer Release
    release_date: 2026-06-01
    cover: /media/images/summer-release-cover.jpg
    synopsis: A short description of this release.
    feed: true
```

## Writing a track

A track is a post with `post_type: music`. See [Posts → Music](/documentation/roe/posts#music) for more information.

The short version: `audio` is the track/mp3, `release` picks which release it belongs to, and `track_number` is its place in the running order. The release property for the post lists the available releases (keys) from the music.yml file.

## Showing a release on your site

Use a [collection](/documentation/roe/collections) filtered to the release, ordered by track number, with the [`playlist` template](/documentation/roe/collections_templates#when-to-use-the-playlist-template):

````markdown
```collection
source: posts
post_type: music
release: summer-release
order: track_number
template: playlist
```
````

`order: track_number` is what gives you the running order. Leave it out and you'll get them by date, which would be unusual for a music release.

For a single track in the middle of an article, use a [player card](/documentation/roe/cards#player) to add that track.

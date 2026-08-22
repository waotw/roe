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

The Music feature lets you publish tracks as posts, group them into releases, and — if you want — hand any release to Apple Podcasts or Spotify as a feed.

## Turning it on

Go to [Admin → Settings](/admin/configs) and click `Enable Music`. Roe creates `site/system/features/music.yml` and opens the Music settings form.

The file's presence is what enables the feature. Delete it and Music turns off; `post_type: music` stops appearing in the post-type list and the `playlist` template disappears from the Collection builder.

## You can start posting straight away

Every track belongs to a release, and Roe seeds one called `singles`. New music posts use it unless you pick something else, so a one-off track has a working player and a place in a track list without you configuring anything.

Gather them all with a collection filtered to `release: singles`. Add a release when you have one.

## Adding a release

Click `+ New Release` in [Settings → Music](/admin/configs/music/edit). A blank release appears in the form.

<mark>Note:</mark> The `Release key` is what collections and tracks use to connect to this release. Renaming it later breaks that link on every track that points to this release, and you'd have to update each one by hand. Short and unlikely-to-change beats descriptive.

## What each setting does

| Setting | What it affects |
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

Nothing here is required unless you turn the feed on. A release with only a `title` works.

The two above the release list — `artist` and `audience` — are the defaults every release falls back to. The can be changed per release.

## How settings are applied from track to release

The most specific settings win: **the track, then its release, then the defaults in music.yml.** If not `Artist` is present, it will fallback to the site author in [site.yml](/admin/configs/site/edit).

Where that actually shows up:

- **Cover art** — if a track has it's own `image`, that is shown. If not, it will use the relase's artwork for the player.
- **Artist and audience** — if a track has it's own artist and audience, this is used. If not, it will fallback to the settings in music.yml for `artist` and `audience`.

So a compilation where one track is by someone else needs `artist:` on that track only, and changing a release's cover updates the player on every track without touching a post.

<mark>Audience on a release does not gate your site.</mark> Whether a page is behind a membership is decided by the post's own `audience` field. A release's `audience` only decides whether its feed is public. Set `audience: paid` on the tracks themselves to restrict the posts.

## Releasing music as a podcast feed

Tick `Release this as a podcast feed` on a release and Roe publishes an RSS feed at `/music/<release-key>.xml`. Submit that URL to Apple Podcasts, Spotify, or any podcatcher.

This is separate from the [Podcast feature](/documentation/roe/podcasts). This allows you to release music as a podcast but you don't have to enable Podcasts in Roe to use it.

### What the feed needs

Apple checks three things when you submit, so Roe asks for the same three before the feed goes live:

- `title`
- `synopsis` — this becomes the feed's description
- `cover` — square artwork; 3000×3000 JPG or PNG is the distribution standard

Tick the box without them and the settings page tells you which are missing. The feed stays off until they're filled in, rather than publishing something a platform would reject.

You also need an author email in [Settings → site](/admin/configs/site/edit). Apple emails that address to confirm you own the feed.

### What Roe fills in for you

- **Category** is always `Music`. Apple validates categories against a fixed list, so your `genre` can't be used there — it travels separately, in tags a podcatcher can read but the big platforms ignore.
- **Track order** comes from `track_number`. The feed is marked as a serial, so players start at track one instead of the newest.
- **Explicit** is set on the whole release if any track on it is marked explicit.
- **Copyright** falls back to `℗ & © <year> <artist>` when you haven't set one.

### Tracks in the feed

Only published tracks on that release appear. Drafts don't, and neither do tracks on other releases.

Each track carries a permanent ID (called a [GUID](/documentation/roe/glossary#guid-globally-unique-identifier)) so podcast apps can tell your tracks apart between refreshes. Roe writes it when a track is first published and won't let it change — the same protection podcast episodes get. You'll see it as `guid` in the editor, greyed out.

### Paid music

Paid tracks work here the way they do everywhere else in Roe. There are two feeds:

- **The public feed** at `/music/<release-key>.xml` leaves paid audio out. With **Show Paid Content** on in [Members](/documentation/roe/members), paid tracks still appear as teasers — title and description, no audio.
- **The private feed** at `/music/<release-key>/private.xml` carries every track with full audio. Each paid member has their own URL, and it appears on a track's page when they're signed in.

Set `audience: paid` on the release to make the whole thing members-only — then there's no public feed at all, only the private one. Set it on individual tracks to sell a release that's part free, part paid.

Turning the feed off removes both.

## Editing the file directly

`EDIT YAML` let's you edit the file directly. You can also edit the file directly in a text editor. Releases live under a `releases:` key:

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

A track is a post with `post_type: music`. See [Posts → Music](/documentation/roe/posts#music) for the fields.

The short version: `audio` is the track/mp3, `release` picks which release it belongs to, and `track_number` is its place in the running order. The release field lists the available releases (keys) from the music.yml file.

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

`order: track_number` is what gives you the running order. Leave it out and you'll get them by date, which is rarely what a release wants.

For a single track in the middle of your writing, use a [player card](/documentation/roe/cards#player) instead.

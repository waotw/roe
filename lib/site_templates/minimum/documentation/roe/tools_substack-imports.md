---
title: Substack Imports
status: published
tags: tool
---

# Importing from Substack

Roe can import your entire Substack publication — posts, media, members, and delivery history — in a guided 4-phase process.

To begin: Go to `Admin → 🛠️ → Substack Imports` & click `NEW IMPORT` 

## What Gets Imported

### Phase 1: Upload

Upload your Substack export ZIP file. You can request an export from your Substack publication's Settings page.

<mark>(note: we don't import any open history into Roe)</mark>

1. Click `Choose File` and select your ZIP export file.
2. Click `UPLOAD & CONTINUE`

### Phase 2: Posts & Media

After uploading, you'll configure and run the posts import. This is the main event — it converts your Substack content into Roe's Markdown format and downloads all media files. 

#### Configuration

**Substack Base URL** — Your publication URL (e.g., `https://yourname.substack.com`). This is used to fetch cover images, podcast URLs, and other data that isn't in the export CSV.

**Filters** (optional):

- `type` — Import only a specific post type: `All Types`, `Newsletter`, `Podcast`, or `Page`
- `after` — Only posts published after this date
- `before` — Only posts published before this date
- for all posts, just leave dates empty

**Options**:

- `include_drafts` — By default, only published posts are imported. Check this to include drafts.

#### Click `START IMPORT`

- Posts are converted from HTML to Markdown
- Images are downloaded to `/site/media/images/`
- Audio files (podcasts) are downloaded to `/site/media/audio/`
- Video files are downloaded to `/site/media/video/`
- Substack's Post Link Embeds are converted to Roe's Post Link Cards
- Substack's Pullquotes are converted to Roe's Pullquote Cards
- Existing posts (matched by Substack ID) are skipped
- Existing media (matched by source URL) are reused
- Missing media (failed downloads) are tracked for manual handling later

### Phase 2B: Missing Media

If the importer is not able to find the media linked in the export (usually paywalled posts), you'll see a note about this after you import Posts.

#### Click `Resolve Missing Media →`

#### How It Works

Posts already have the expected media url in their frontmatter (e.g., `audio: /media/audio/post-slug.mp3`). You just need to get the file to that location, and the post will find it automatically.

#### 2 ways to find missing media:

1. Add URLs to the he missing media page. The URL you need is a link to the actual file on Substack's servers.
2. Download the file and upload it on the Media page, then come back to this Import. You'll need to name the file so it matches what is being used in the Posts in Roe (e.g., `/media/audio/post-slug.mp3`).

#### Bulk Actions

- Retry Live Fetch — Re-fetches the live Substack pages for posts with missing media, attempts to download with fresh URLs
- Verify All Media Connections — Scans all media files and checks if they’re properly connected to posts

#### Click `VERIFY ALL MISSING MEDIA`

When all missing media is found/connected (or if you don't care about this)…

#### Click `CONTINUE TO MEMBERS IMPORT →`

### Phase 3: Members

Imports your subscriber list from the `email_list.*.csv` in your export.

#### Options

- **Auto-set lifetime members to paid** — Members with a `lifetime` Substack plan will be set to `tier: paid`
- **Auto-gift all paid members** — All paid plan members (monthly, yearly, quarterly, etc.) will be set to `tier: paid`

If neither option is checked, imported members default to `tier: free` regardless of their Substack plan.

#### Click `START MEMBER IMPORT`

- Members with active subscriptions or enabled emails are imported
- Inactive members and those with disabled emails are discarded
- Existing members (matched by email) are updated rather than duplicated
- Name is extracted from email (e.g., `john.doe` from `john.doe@email.com`)
- Substack plan information is stored in member data

**Supported Substack plans:** `lifetime`, `monthly`, `quarterly`, `semiannually`, `yearly`, `ios_app`, `comp`, `other`

#### Click `CONTINUE TO DELIVERIES →`

### Phase 4: Deliveries

Imports delivery history:

- records of which members received which posts and when.
- This requires Phase 2 (Posts) and…
- Phase 3 (Members) to be completed first.

#### What Happens

- Each `*.delivers.csv` file is matched to the corresponding post in Roe and the imported Members
- Delivery records are created linking posts to members with timestamps
- Deliveries are skipped if the member wasn't imported in Phase 3
- Duplicate deliveries are skipped

#### Click `START DELIVERY IMPORT`

---

## Content Conversion

The importer converts Substack's HTML into Roe's Markdown format. Here's how each element is handled:

### Substack-Specific Elements

Roe supports many of the special elements used in Substack

- Post Link Embeds → [Post Link Cards](/documentation/cards#post-link)
- Pullquotes → [Pull quotes](/documentation/cards#pull-quote)
- Image Galleries → [Galleries](/documentation/galleries)
- Image with Caption → [Captions](/documentation/galleries#captions)
- Footnotes → [The Editor](/documentation/the-editor#buttons)
- Poetry 

It will import Audio and Video podcast posts.

### Elements Not Imported

The following Substack elements are not currently supported but may be in the future:

- LaTex
- Recipe

The following Substack features will not be supported:

- Notes/Embedded notes
- Polls
- Comments
- Finacial chart

---

## Frontmatter Mapping

Each imported post gets YAML frontmatter with these fields:

| Substack Field | Roe Frontmatter | Notes |
|---|---|---|
| post_id | `substack_post_id` | Stored in metadata for deduplication |
| slug | `url_name` | Used as filename |
| title | `title` | |
| subtitle | `subtitle` | |
| post_date | `date` | ISO 8601 format |
| type | `post_type` | See mapping below |
| is_published | `status` | `published` or `draft` |
| audience | `audience` | See mapping below |
| cover_image | `image` | Local path: `/media/images/slug-cover.ext` |
| podcast_url | `audio` | Local path: `/media/audio/slug.mp3` |
| video mux id | `video` | Local path: `/media/video/slug.mp4` |

### Post Type Mapping

| Substack Type | Roe Post Type |
|---|---|
| newsletter | `article` |
| podcast | `podcast` |
| video | `video` |
| page | `page` |
| (other) | `article` |

### Audience Mapping

| Substack Audience | Roe Audience |
|---|---|
| paid, premium | `paid` |
| public, free | `everyone` |
| (other) | `everyone` |

### Podcast-Specific Fields

For podcast posts, additional frontmatter is added:

- `podcast_duration`
- `podcast_episode_number`
- `podcast_season_number`
- `podcast_episode_type`

---

## Media Handling

### Where Media Is Stored

| Type | Path | Naming Convention |
|---|---|---|
| Cover images | `/site/media/images/` | `slug-cover.jpg` (or original extension) |
| Inline images | `/site/media/images/` | `slug-1.jpg`, `slug-2.jpg`, etc. |
| Audio (podcasts) | `/site/media/audio/` | `slug.mp3` |
| Video | `/site/media/video/` | `slug.mp4` |

### Smart Media Handling

- **Existing media is reused** — If an image/audio/video was already downloaded (by a previous import or manual upload), it won't be downloaded again
- **Pre-existing files are tracked** — Files that already exist on disk are registered in the database without associating them with the current import, so rollback won't delete them
- **HEIC images are converted** — If the `vips` library is available, HEIC/HEIF images are automatically converted to JPEG during download
- **Remote URLs are replaced** — After download, all remote URLs in the Markdown body are replaced with local paths

### Missing Media

Some media can't be downloaded automatically — typically paywalled content, Mux-hosted videos, or files behind authentication. These are tracked in the import stats and can be resolved later via the **Resolve Missing Media** interface.

---

## Rollback

Every import can be fully rolled back. Clicking **Rollback Import** will:

- Delete all posts created by the import
- Delete all media files created by the import (from disk and database)
- Remove member records created by the import
- Remove delivery records created by the import

Pre-existing files that were tracked but not created by this import are preserved.

---

## Re-Importing

Running the import again is safe:

- Posts that already exist (matched by `substack_post_id` in metadata) are skipped
- Media that already exists (matched by `source_url`) is reused
- The live fetch step is skipped for posts that already exist in the database

This means you can run the import multiple times without creating duplicates. It's useful for picking up new posts published since your last import.

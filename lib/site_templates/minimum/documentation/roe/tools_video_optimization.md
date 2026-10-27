---
title: Video Optimization
status: published
tags: tool
---

# Video optimization in Roe

Video files get big fast. A few minutes from a phone can be hundreds of megabytes, and serving that file as-is makes pages slow and eats up your live site's storage. Roe handles video optimization for you automatically: it makes smaller web versions (variants) of each video you upload and plays those in place of the original. To do this, you'll need to install `ffmpeg`, an industry standard video tool.

Without `ffmpeg`, videos still work. They're just served at their original size.

## Enable automatic video optimization

Install `ffmpeg` on the same computer you're using Roe, with `roe install ffmpeg` in your terminal or to go [Admin → 🛠️ → Images & Video ↗](/admin/dependencies), and follow the instructions there.

Roe makes the web variants on your computer, and [Site Sync](/documentation/roe/site-sync) sends them to your live site. Your live site doesn't need `ffmpeg`.

## The variants that Roe creates

When you upload a video, Roe creates variants in the background, one video at a time. You can watch the progress on the video's card on the [Media](/admin/medium) page in Admin.

| File | What it's for |
|---|---|
| `720p` | Played by default |
| `1080p` | Offered as a second, sharper version, only when your original is at least 1080p |
| `poster` | The still image shown before the video plays |

A few things Roe takes care of along the way:

- **It never makes a variant bigger than your original.** A 720p video gets a 720p variant only.
- **Vertical video stays vertical.** Sizes are calculated using the shorter side, so a vertical phone video counts as 1080p.
- **It plays everywhere.** Variants are standard H.264 MP4s, which every browser can play.
- **It starts quickly.** Videos are set up so they can start playing before they've finished downloading.
- **It removes your location.** Phones save where a video was filmed. Roe leaves that out of the web variants; the original is untouched.
- **It skips a variant that wouldn't help.** If your original is already a small, web-ready MP4 and a variant would save less than 10%, Roe plays your original instead.
- **It picks a good poster.** The poster frame comes from somewhere in the middle of the video, skipping black or very dark frames.

Your original is never changed. Roe keeps it as the archive copy and doesn't put it on the page once the variants are ready.

## Videos added before ffmpeg was installed

Videos you uploaded before installing `ffmpeg` don't have web variants yet. Go to [Media](/admin/medium) and click `OPTIMIZE VIDEOS`. The button only shows when there are videos with no web variants, and it also picks up any video that never finished.

It runs in the background, one video at a time, and can take a while for longer videos.

## Videos on your live site

Your live site plays the web variants, never the original video, so the original will only take up space on the live site. In [Settings → Site → Site Sync](/admin/configs/site/edit), **Largest video on the live site** controls what goes live:

| Setting | What goes to your live site |
|---|---|
| `1080p` (default) | The web variants. Originals stay on this computer. |
| `720p` | Only the 720p variant and the poster |
| `Original` | Every file, including the original |

Your computer always keeps all variants and the original file. If a video doesn't have web variants yet the original will be used, since that's the only video file available.

If you upload a video directly on your live site, it will use the original size. Add videos locally, wait for the variants to be created and sync your site to use the web variants on the live site.

## Add optimized videos manually

You can make the web variants yourself, for example with your own encoder settings, and Roe will serve them. `ffmpeg` is only needed to _create_ them, never to _serve_ them.

Videos are a bit trickier than images. Next to the variants, Roe needs a small `{original-name}-video.json` file describing them, and that file has to match your original exactly. For most sites it's easier to let Roe do it.

### Where to put them

Roe looks for web versions of the video in a `variants/` folder next to your original, inside your site's `media/video/` folder.

```bash
site/
└── media/
    └── video/
        ├── clip.mov    ← your original (kept on disk, never on the page)
        └── variants/
            ├── clip-720p.mp4
            ├── clip-1080p.mp4
            ├── clip-poster.jpg
            └── clip-video.json
```

### Naming format

```
{original-name}-{variant}.{ext}
```

- **`{original-name}`** - the original filename without its extension (`clip` for `clip.mov`)
- **`{variant}`** - `720p`, `1080p` or `poster`
- **`{ext}`** - always `.mp4` for the videos and `.jpg` for the poster, whatever the original's extension

### The `-video.json` file

This tells Roe which variants exist and how big they are. Roe only uses the variants listed in it. In this example, the orignal file is `clip.mov`. So the `json` file is named: `clip-video.json`.

```json
{
  "source": { "path": "/media/video/clip.mov", "size": 78778458 },
  "variants": [
    { "name": "720p", "path": "/media/video/variants/clip-720p.mp4", "width": 1280, "height": 720 },
    { "name": "1080p", "path": "/media/video/variants/clip-1080p.mp4", "width": 1920, "height": 1080 }
  ],
  "poster": "/media/video/variants/clip-poster.jpg",
  "complete": true
}
```

- **`source.size`** must be your original's exact size in bytes. If you replace the original, Roe sees the size has changed and stops using the existing variants.
- **`width`** and **`height`** are each variant's size in pixels.
- Leave out any variant you didn't make. A 1080p variant isn't needed for a 720p original.

### Sizes

| Variant | Shorter side | Use it for |
|---|---|---|
| `720p` | **720px** | The variant that plays by default |
| `1080p` | **1080px** | Only when your original's shorter side is 1080px or more |

Make them as H.264 MP4s with AAC audio so they play in every browser.

### Extensions

Originals can be `.mp4`, `.m4v`, `.mov`, `.webm`, `.mkv`, `.avi` or `.ogv`.

### How Roe works with web variants

Roe switches to the web variants as soon as they're listed in the `-video.json` file and on disk. Until then it plays your original. If `ffmpeg` is installed, Roe only makes the variants that are missing, so hand-made files aren't overwritten.

If you delete or replace an original, Roe removes its old web variants too.

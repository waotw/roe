---
title: Image Optimization
status: published
tags: tool
---

# Image optimization in Roe

Roe will handle all image optimization for you automatically. In order to do this, you'll need to install `libvips`, an industry standard image manipulation library. 

You can also [add your own optimized images](#add-optimized-images-manually) and Roe will use those. This is perfect for a smaller site with a handful of images. 

## Enable automatic image optimization

Get started here: [Admin → 🛠️ → Images ↗](/admin/dependencies) and follow the instructions. 

## Add optimized images to Roe manually

Prefer to optimize images yourself, or running on a host without `libvips`? Drop the optimized versions in and Roe serves them exactly as if it had generated them. libvips is only needed to _create_ variants - never to _serve_ them.

### Where to put the variants

Roe looks for variants in a `variants/` folder sitting right next to your original image, inside your site's `media/images/` folder. Your original stays put as the archive copy - Roe never serves it directly, only the variants.

```bash
site/
└── media/
    └── images/
        ├── photo.jpg    ← your original (kept on disk, never served)
        └── variants/
            ├── photo-thumb.jpg
            ├── photo-thumb.webp
            ├── photo-small.jpg
            ├── photo-small.webp
            ├── photo-medium.jpg
            ├── photo-medium.webp
            ├── photo-large.jpg
            ├── photo-large.webp
            ├── photo-xl.jpg
            └── photo-xl.webp
```

### Naming format

Every variant follows the same pattern:

```
{original-name}-{size}.{ext}
```

- **`{original-name}`** - the original filename without its extension (`photo` for `photo.jpg`)
- **`{size}`** - one of `thumb`, `small`, `medium`, `large`, `xl` (see below)
- **`{ext}`** - the same extension as the original, **plus a matching `.webp` copy of each**

So `sunset.png` becomes `sunset-thumb.png`, `sunset-small.png`, … _and_ `sunset-thumb.webp`, `sunset-small.webp`, ….

### Sizes

| Size | Dimensions | How to resize |
|---|---|---|
| `thumb` | **150 × 150** | crop to a centered square |
| `small` | up to **400 × 400** | scale to fit, keep aspect ratio |
| `medium` | up to **800 × 800** | scale to fit, keep aspect ratio |
| `large` | up to **1200 × 1200** | scale to fit, keep aspect ratio |
| `xl` | up to **1800 × 1800** | scale to fit, keep aspect ratio |

Apart from `thumb` (a square centre-crop image), each size is keeps it's aspect ratio. Roe will consider the image's longest side as it's `size`. 

Because Roe never upscales, you only need variant sizes up to your image's own size - every file smaller than your original's longest side, plus the first size that's equal to or larger than it.

Example: a 1000px-wide photo needs

- `thumb`
- `small`
- `medium`
- `large` - larger than the original, so the original is used
    - `xl` - isn't needed and will be ignored since it's larger than the original

For the `.webp` copies, quality **85** matches what Roe uses.

### Extensions

Originals can be `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`.

- **HEIC / HEIF** - best to steer clear of these formats. Browsers will not render them. Stick with `.jpg`, `.png`, or `.webp`. (During a Substack import Roe will convert HEIC to JPEG for you if `libvips` is installed.)

### How Roe works with variants

Roe switches to the optimized `<picture>` as soon as the **complete** set for an image is present - every required size _and_ its `.webp` sibling. If anything is missing it serves your original instead (and, if libvips is installed, quietly fills in the rest). Hand-placed files are never overwritten, so you can mix manual and automatic freely - Roe only generates what's missing, and picks up your files the next time the page renders.

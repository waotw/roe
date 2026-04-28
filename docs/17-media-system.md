# Media System

Roe handles media uploads, image variant generation, responsive images, and media references across content types.

## Architecture Overview

```
Upload
   │
   ▼
┌─────────────────────────────────────┐
│   Admin::MediumController           │
│   • Receive file                    │
│   • Determine type                  │
│   • Store in site/media/            │
└──────────────┬──────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
      ▼                 ▼
┌──────────┐     ┌──────────────┐
│  Image   │     │   Audio/     │
│  Variant │     │   Video      │
│ Generator│     │              │
│          │     │Duration      │
│• Large   │     │Extractor     │
│• Medium  │     │              │
│• Small   │     │              │
│• Thumb   │     │              │
└────┬─────┘     └──────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│   MediaReference                    │
│   (Join table)                      │
│                                     │
│   post_id ↔ medium_id               │
│   Tracks which content uses         │
│   which media                       │
└─────────────────────────────────────┘
```

**Graph Note:** Media system connects to Content Management, Admin UI, and Static Generation communities (15+ edges).

## Directory Structure

```
site/media/
├── audio/              # Audio files (podcasts, etc.)
│   └── episode-1.mp3
├── images/             # Original images
│   ├── photo-1.jpg
│   ├── photo-2.png
│   └── variants/       # Auto-generated sizes
│       ├── photo-1_large.webp
│       ├── photo-1_medium.webp
│       ├── photo-1_small.webp
│       └── photo-1_thumb.webp
└── video/              # Video files
    └── demo.mp4
```

## Media Model

File: `app/models/medium.rb`

### Key Methods

```ruby
# Media type detection
def image?
  file.content_type.start_with?('image/')
end

def audio?
  file.content_type.start_with?('audio/')
end

def video?
  file.content_type.start_with?('video/')
end

# Variant paths
def variant_path(size)
  "site/media/images/variants/#{filename}_#{size}.webp"
end

# All variants ready?
def variants_ready?
  variant_sizes.all? { |size| File.exist?(variant_path(size)) }
end
```

## Image Variant Generation

File: `app/services/image_variant_generator.rb`

### Generated Sizes

| Size | Dimensions | Use Case |
|------|------------|----------|
| `large` | 1200px width | Full-width images, galleries |
| `medium` | 800px width | Content body, cards |
| `small` | 400px width | Thumbnails, mobile |
| `thumb` | 200px width | Lists, admin previews |

### Variant Format

All variants are generated as **WebP** for optimal compression:

```ruby
# image_variant_generator.rb
def generate_variants
  sizes = {
    large: 1200,
    medium: 800,
    small: 400,
    thumb: 200
  }
  
  sizes.each do |name, width|
    resize_image(width)
    convert_to_webp
    save_to_variants_directory
  end
end
```

### Background Job

Variant generation runs asynchronously:

```ruby
# After upload
ImageVariantGenerationJob.perform_later(medium)

# Job
class ImageVariantGenerationJob
  def perform(medium)
    ImageVariantGenerator.generate(medium)
  end
end
```

## Responsive Images

File: `app/services/responsive_image_renderer.rb`

### Automatic srcset Generation

```erb
<%= responsive_image_tag(
  path: "media/images/photo.jpg",
  alt: "Description",
  sizes: "(max-width: 600px) 400px, 800px"
) %>
```

Renders:

```html
<picture>
  <source 
    srcset="/media/images/variants/photo_small.webp 400w,
            /media/images/variants/photo_medium.webp 800w,
            /media/images/variants/photo_large.webp 1200w"
    sizes="(max-width: 600px) 400px, 800px"
    type="image/webp">
  <img 
    src="/media/images/photo.jpg"
    alt="Description"
    loading="lazy">
</picture>
```

### Lazy Loading

All responsive images include `loading="lazy"` by default for performance.

### Fallback

If variants aren't ready yet, falls back to original image with appropriate sizing.

## Media References

File: `app/models/media_reference.rb`

### Tracking Usage

```ruby
class MediaReference < ApplicationRecord
  belongs_to :reference, polymorphic: true  # Post, Page, Product, etc.
  belongs_to :medium
  
  # Tracks which content uses which media files
  # Enables: cleanup orphaned media, usage reports, etc.
end
```

### Automatic Tracking

When you reference an image in content:

```markdown
![Alt text](media/images/photo.jpg)
```

ContentSync automatically creates:

```ruby
MediaReference.create!(
  reference: post,
  medium: Medium.find_by(path: "media/images/photo.jpg"),
  usage_type: 'content_image'
)
```

### Usage Report

```ruby
# Find all posts using a specific image
medium.posts

# Find orphaned media (not referenced anywhere)
Medium.left_outer_joins(:media_references)
      .where(media_references: { id: nil })
```

## Upload Process

### Via Admin UI

1. **Admin → Media → Upload**
2. Drag & drop or select files
3. Automatic type detection
4. Stored in appropriate `site/media/` subdirectory
5. Background job generates variants (images only)

### Via Direct Upload

```ruby
# Programmatic upload
medium = Medium.create!(
  file: File.open('/path/to/file.jpg'),
  title: "Photo Description"
)
```

### Supported Formats

**Images:**
- JPEG, PNG, GIF, WebP, SVG
- Max file size: 10MB (configurable)

**Audio:**
- MP3, WAV, OGG, M4A
- Duration auto-extracted

**Video:**
- MP4, MOV, WebM

## Media Browser

File: Admin UI media picker component

### Features

- Grid view with thumbnails
- Search by filename
- Filter by type (images, audio, video)
- Select for insertion
- Bulk operations (delete, regenerate variants)

### Picker Integration

In post editor:

```erb
<%= media_picker_field :featured_image %>
```

Opens modal:
- Browse existing media
- Upload new file
- Preview before selection

## Duration Extraction

File: `app/services/media_duration_extractor.rb`

Automatically extracts duration from audio/video files:

```ruby
# Returns seconds
duration = MediaDurationExtractor.call("site/media/audio/podcast.mp3")
# => 3600
```

Used for:
- Podcast episode duration in RSS feed
- Video length display
- Content metadata

## Cleanup & Maintenance

### Missing Media Tracking

File: `site/missing_media.yml`

Tracks references to non-existent files:

```yaml
---
- post: "2024-01-15-hello.md"
  missing: "media/images/deleted-photo.jpg"
  referenced_at: "2024-01-20T10:00:00Z"
```

### Orphan Cleanup

```bash
# Find unreferenced media
bin/rails media:cleanup

# Preview what would be deleted
bin/rails media:cleanup --dry-run
```

### Regenerate Variants

```bash
# Regenerate all image variants
bin/rails images:generate_variants

# For specific image
bin/rails images:generate_variants[media/images/photo.jpg]
```

## Static Generation

Media handling during static site build:

1. **Copy originals**: `site/media/` → `output/media/`
2. **Copy variants**: `site/media/images/variants/` → `output/media/images/variants/`
3. **Rewrite URLs**: Update media paths in generated HTML
4. **Verify**: Check all referenced media exists in output

## Configuration

### Max File Size

```ruby
# config/initializers/media.rb
Rails.configuration.max_upload_size = 10.megabytes
```

### Variant Sizes

```ruby
# config/initializers/media.rb
Rails.configuration.image_variants = {
  thumb: 200,
  small: 400,
  medium: 800,
  large: 1200
}
```

### Storage

Media stored in `site/media/` directory (file system). For S3/CDN:

1. Sync `site/media/` to S3 bucket
2. Configure CDN origin
3. Update `MEDIA_URL` environment variable
4. Variants generated locally, uploaded to CDN

## Troubleshooting

### Images not showing

**Check:**
- File exists in `site/media/images/`
- Path in content is correct (relative to site/)
- Variants generated (check variants/ directory)
- MediaReference exists

### Upload fails

**Check:**
- File size under limit
- Supported file format
- Disk space available
- File permissions on `site/media/`

### Variants not generating

**Check:**
- ImageMagick/FFmpeg installed
- Background job queue running
- Check job logs for errors
- Manually run: `ImageVariantGenerator.generate(medium)`

### Slow page loads

**Check:**
- Using responsive_image_tag (not plain img tags)
- Variants pre-generated
- WebP format being served
- Lazy loading enabled

## Best Practices

### Image Optimization

Before upload:
- Resize to reasonable dimensions (max 2400px)
- Use appropriate format (JPEG for photos, PNG for graphics)
- Compress with tools like ImageOptim
- Let Roe handle WebP conversion

### Organization

```
site/media/images/
├── posts/          # Featured images for posts
├── products/       # Product images
├── documentation/  # Docs screenshots
└── site/           # Site-wide images (logo, etc.)
```

### Naming

- Use descriptive names: `ruby-conference-talk.jpg`
- Avoid spaces: use hyphens
- Include dimensions if relevant: `hero-1200x600.jpg`
- Version if updating: `diagram-v2.png`

### Alt Text

Always provide alt text:

```markdown
![Ruby code showing class definition](media/images/code-example.jpg)
```

## Related

- [Content System](./02-content-system.md) - Referencing media in content
- [Sync & Generation](./05-sync-generation.md) - Media handling during sync
- [Admin UI](./07-admin-ui.md) - Media browser and picker
- [Podcasts](./13-podcasts.md) - Audio file handling

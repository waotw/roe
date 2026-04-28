# Substack Importer

Roe provides a multi-phase importer for migrating content from Substack, handling posts, members, and email delivery history while preserving audience relationships.

## Architecture Overview

```
Substack Export ZIP
      │
      ▼
┌─────────────────────────────────────┐
│   Admin::ImportsController          │
│   • Upload and extract              │
│   • Detect archive structure        │
└──────────────┬──────────────────────┘
               │
      ┌────────┴────────┐
      │                 │
      ▼                 ▼
┌──────────┐      ┌──────────┐
│ Phase 1  │      │ Phase 2  │
│ Posts    │      │ Members  │
│          │      │          │
│ImportPostsJob│  │ImportMembersJob│
└────┬─────┘      └────┬─────┘
     │                 │
     │            ┌────┴────┐
     │            │ Phase 3 │
     │            │Deliveries
     │            │         │
     │            │ImportDeliveriesJob
     │            └────┬────┘
     │                 │
     └────────┬────────┘
              ▼
┌─────────────────────────────────────┐
│   Converter Service                 │
│   (HTML → Markdown)                 │
└─────────────────────────────────────┘
```

**Graph Note:** The Substack Import Jobs form a distinct community (10 nodes) including ImportDeliveriesJob, ImportMembersJob, ImportPostsJob, and the Converter service.

## Export from Substack

### Download Export

1. Substack Dashboard → Settings → Export
2. Download the ZIP file (contains posts, subscribers, analytics)
3. The ZIP structure:
   ```
   export/
   ├── posts/
   │   ├── post-*.html
   │   └── post-*_metadata.json
   ├── subscribers.csv
   ├── podcast/
   │   └── *.mp3
   └── media/
       └── images/
   ```

### Prepare for Import

Optional: Use the trim utility to reduce export size:

```bash
bin/trim_substack_export export.zip --ensure-podcasts 5
```

This removes old analytics while ensuring 5 most recent podcast episodes are included.

## Import Phases

### Phase 1: Posts (ImportPostsJob)

Converts HTML posts to Markdown and creates local posts.

```ruby
class ImportPostsJob
  def perform(import_id)
    import = Import.find(import_id)
    posts_dir = extract_archive(import)
    
    Dir.glob("#{posts_dir}/*.html").each do |html_file|
      metadata = JSON.parse(File.read(html_file.sub('.html', '_metadata.json')))
      
      # Convert HTML to Markdown
      markdown = Converter.convert(html_file)
      
      # Create post
      Post.create!(
        title: metadata['title'],
        content: markdown,
        published_at: metadata['post_date'],
        imported: true,
        import_source: 'substack',
        audience: map_audience(metadata['audience'])
      )
    end
    
    import.mark_phase_complete!(:posts)
    ImportMembersJob.perform_later(import.id)
  end
end
```

#### Audience Mapping

| Substack Audience | Roe Audience |
|-------------------|--------------|
| `everyone` | `public` |
| `only_paid` | `paid` |
| `founding` | `paid` |
| `only_free` | `free` |

### Phase 2: Members (ImportMembersJob)

Imports subscribers and creates member accounts.

```ruby
class ImportMembersJob
  def perform(import_id)
    import = Import.find(import_id)
    csv_path = extract_subscribers_csv(import)
    
    CSV.foreach(csv_path, headers: true) do |row|
      member = Member.find_or_initialize_by(email: row['email'])
      
      member.assign_attributes(
        subscribed_at: row['created_at'],
        subscription_tier: map_tier(row['subscription_type']),
        import_source: 'substack'
      )
      
      if member.new_record?
        member.generate_token!
        MemberMailer.welcome(member).deliver_later
      end
      
      member.save!
    end
    
    import.mark_phase_complete!(:members)
    ImportDeliveriesJob.perform_later(import.id)
  end
end
```

#### Subscription Tier Mapping

| Substack Type | Roe Status |
|---------------|------------|
| `free` | `free` (no subscription) |
| `paid` | `paid` with Stripe integration |
| `founding` | `paid` (highest tier) |
| `gift` | `paid` (complimentary) |

**Important:** Payment information is NOT imported. Members marked as `paid` will need to re-subscribe via Stripe checkout, or you can manually upgrade them in admin.

### Phase 3: Deliveries (ImportDeliveriesJob)

Records which members received which emails (for analytics).

```ruby
class ImportDeliveriesJob
  def perform(import_id)
    import = Import.find(import_id)
    
    # Match Substack posts to imported posts
    import.posts.each do |post|
      deliveries = find_deliveries_for_post(post, import)
      
      deliveries.each do |delivery|
        member = Member.find_by(email: delivery['email'])
        next unless member
        
        NewsletterSend.create!(
          post: post,
          member: member,
          sent_at: delivery['sent_at'],
          status: map_delivery_status(delivery['status']),
          imported: true
        )
      end
    end
    
    import.mark_phase_complete!(:deliveries)
    import.mark_complete!
  end
end
```

## HTML to Markdown Conversion

File: `app/services/substack_importer/converter.rb`

The converter handles Substack-specific HTML elements:

### Supported Conversions

| Substack Element | Markdown Output |
|------------------|-----------------|
| Paywall blocks | `[Paid content...]` placeholder |
| Tweet embeds | Link to tweet |
| Audio embeds | `![Audio](url)` |
| Image galleries | Markdown image tags |
| Footnotes | Markdown footnotes syntax |
| Code blocks | Fenced code blocks |
| Blockquotes | `>` prefix |

### Example Conversion

**Substack HTML:**
```html
<div class="subscriber-content">
  <p>Premium content here...</p>
</div>
```

**Roe Markdown:**
```markdown
[Paid content - available to subscribers]
```

### Custom Processing

Add custom converters:

```ruby
# config/initializers/substack_import.rb
SubstackImporter::Converter.register_processor do |node|
  if node['class']&.include?('custom-element')
    "<!-- Custom: #{node.text} -->"
  end
end
```

## Media Migration

### Image Handling

Images are copied from Substack export to local media:

```ruby
class MediaHandler
  def self.migrate(import, post)
    post.content.scan(/images\.substack\.com\/[^\s)]+/).each do |url|
      # Download image
      download = Down.download(url)
      
      # Upload to local media
      medium = Medium.create!(
        file: download,
        source: 'substack_import',
        imported_at: Time.current
      )
      
      # Update post content with new URL
      post.content.gsub!(url, medium.url)
    end
    
    post.save!
  end
end
```

### Audio/Podcast Migration

Audio files are handled specially:

1. Copy from `export/podcast/*.mp3` to `site/media/audio/`
2. Extract duration using `MediaDurationExtractor`
3. Create podcast posts with `post_type: podcast`
4. Preserve episode order via `episode_number`

## Admin Interface

### Import Dashboard

**Admin → Imports:**

- Upload Substack export ZIP
- View 3-phase progress
- See success/error counts per phase
- Download error logs
- Retry failed phases

### Import Status Page

```
Import #123 - Substack Export

Phase 1: Posts ✓ Complete
  45 posts imported
  2 errors (view log)

Phase 2: Members ✓ Complete
  1,234 members imported
  890 free, 344 paid

Phase 3: Deliveries ⏳ In Progress
  12,456 deliveries recorded
  Estimated: 5 minutes remaining
```

### Manual Actions

- **Retry Phase**: Re-run a specific phase
- **Rollback**: Delete all imported content (if < 24hrs)
- **Download Log**: Get detailed error report

## Configuration

No special configuration needed, but ensure:

1. **Storage**: Sufficient disk space for media downloads
2. **Memory**: Large imports may require increased job memory
3. **Timeouts**: Network downloads may need timeout adjustments

## Best Practices

### Before Import

1. **Backup**: Export your current Roe content
2. **Test**: Run import on staging first
3. **Clean**: Use `trim_substack_export` to remove unnecessary data
4. **Notify**: Let subscribers know about platform migration

### During Import

1. **Monitor**: Watch job logs for errors
2. **Incremental**: Import in batches if > 1000 posts
3. **Review**: Check sample of converted posts
4. **Media**: Verify images/audio migrated correctly

### After Import

1. **Verify**: Check post formatting, links, images
2. **Redirects**: Set up URL redirects from Substack
3. **Email**: Update newsletter template with new branding
4. **Stripe**: Guide paid members to re-subscribe

## Troubleshooting

### Import fails immediately

**Check:**
- ZIP file is valid Substack export
- Disk space available for extraction
- Import job queue is running

### Posts have formatting issues

**Check:**
- Custom Substack elements not supported
- HTML entities not decoded
- Image URLs not updated

**Fix:**
- Manual edit in admin
- Add custom converter
- Re-import specific post

### Members not imported

**Check:**
- subscribers.csv present in ZIP
- CSV format matches expected columns
- No duplicate email validation errors

### Media not downloading

**Check:**
- Original URLs still accessible
- Network timeout not exceeded
- Storage quota not exceeded

## Related

- [Content System](./02-content-system.md) - Post structure and frontmatter
- [Members & Authentication](./11-members-authentication.md) - Member model
- [Email & Newsletters](./14-email-newsletters.md) - Delivery tracking
- [Podcasts](./13-podcasts.md) - Podcast import from RSS

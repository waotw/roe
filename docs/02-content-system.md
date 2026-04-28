# Content System

Content lives in the `site/` directory as Markdown files with YAML frontmatter.

## Directory Structure

```
site/
├── posts/           # Blog posts (content_type: post)
│   ├── 2024-01-15-hello-world.md
│   └── tech/
│       └── 2024-02-01-new-framework.md
├── pages/           # Static pages (content_type: page)
│   ├── home.md
│   └── about.md
├── documentation/   # Documentation (content_type: documentation)
│   ├── getting-started.md
│   └── api-reference.md
├── layout/          # Site layout templates
│   ├── navigation.md
│   └── footer.md
├── media/           # Uploaded media
│   ├── images/
│   └── files/
└── system/          # Configuration (not synced as content)
    ├── site.yml
    ├── assets/
    │   ├── fonts/
    │   └── images/
    └── defaults/
        ├── cards.yml
        └── collections.yml
```

## File Format

```markdown
---
title: My Post Title
date: 2024-01-15
tags: [tech, ruby]
status: published
author: Darren Allen
featured_image: /media/images/cover.jpg
---

# Markdown content starts here

This is the body of the post.
```

## Frontmatter Schema

### Universal Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | Yes | Display title |
| `date` | string | No | Publication date (YYYY-MM-DD) |
| `status` | string | No | `draft`, `published`, or `unlisted` |
| `tags` | array | No | Content categorization |
| `slug` | string | No | URL slug (auto-generated from title if absent) |
| `featured_image` | string | No | Cover/thumbnail image path |
| `description` | string | No | SEO description |

### Post-Specific Fields

| Field | Type | Description |
|-------|------|-------------|
| `post_type` | string | `article`, `music`, `podcast`, `image` |
| `author` | string | Author name |

### Page-Specific Fields

| Field | Type | Description |
|-------|------|-------------|
| `template` | string | Custom template name |
| `show_in_nav` | boolean | Include in navigation |

### Documentation-Specific Fields

| Field | Type | Description |
|-------|------|-------------|
| `order` | integer | Sort order within section |
| `section` | string | Documentation section |

## Status System

Three content statuses control visibility:

| Status | Public | In Feeds | In Collections | Direct URL |
|--------|--------|----------|----------------|------------|
| `draft` | No | No | No | No |
| `published` | Yes | Yes | Yes | Yes |
| `unlisted` | Yes | No | Yes | Yes |

### Setting Status

```markdown
---
title: Draft Post
status: draft
---

This post is only visible in the admin.
```

```markdown
---
title: Unlisted Post
status: unlisted
---

This post has a direct URL but doesn't appear in feeds or archives.
```

## Content Type Detection

Content type is determined by file location:

| Path | Content Type | Model |
|------|--------------|-------|
| `site/posts/**/*.md` | post | `Post` |
| `site/pages/**/*.md` | page | `Page` |
| `site/documentation/**/*.md` | documentation | `Documentation` |

## URL Generation

URLs are generated from slug metadata or derived from filename/title:

```
site/posts/hello-world.md      → /posts/hello-world
site/posts/tech/new-api.md     → /posts/tech/new-api
site/pages/about.md            → /about
site/documentation/api.md      → /documentation/api
```

With date prefix (auto-stripped):
```
site/posts/2024-01-15-my-post.md → /posts/2024-01-15-my-post
```

## Accessing Metadata

Use dynamic attribute access via the `HasMetadata` concern:

```ruby
post = Post.find(1)
post.title           # => "My Post"
post.tags            # => ["tech", "ruby"]
post.author          # => "Darren Allen"
post.url_name        # => "my-post" (from slug or title)
```

Query by metadata:

```ruby
Post.published.tagged_with("ruby")
Post.by_type("article")
Post.feed_posts  # published + ordered by date
```

## Inline Footnotes

Use `(*footnote text*)` syntax for footnotes:

```markdown
This is text with a footnote(*This is the footnote*).
```

Renders as:

```html
This is text with a footnote<sup id="fnref-1"><a href="#fn-1">1</a></sup>.
<!-- and at bottom -->
<footer>
  <div class="footnotes">
    <ol>
      <li id="fn-1">This is the footnote <a href="#fnref-1">↩</a></li>
    </ol>
  </div>
</footer>
```

## Related

- [Collections](./03-collections.md) - Grouping content by metadata
- [Markdown Extensions](./04-markdown-extensions.md) - Cards, galleries, pullquotes
- [Configuration](./06-configuration.md) - site.yml structure
- [Members & Authentication](./11-members-authentication.md) - Access control and content gating
- [Podcasts](./13-podcasts.md) - Podcast post type and audio content
- [Media System](./17-media-system.md) - Image variants and media handling

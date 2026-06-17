---
title: Metadata Fields
status: published
---

# Metadata Fields
Metadata appears at the top of each markdown file:
```markdown
---
title: The Literary Wasteland, 2
subtitle: The Literary Mediocrity
date: 2024-05-22
status: published
post_type: article
---
```

The admin separates this into a dedicated textarea, but it's part of the same file.

![Metadata in Admin](/media/images/metadata-admin.png)

## Available Fields

### Shared by Posts and Pages
```
title: Post/Page Title
subtitle: Secondary Heading
url_name: Custom URL slug (computed from title if not provided)
excerpt: Short description of page/post
status: draft/pubhlished/unlisted
```

**title (required)**

The primary heading for the post or page. Displayed in templates and browser titles.

**subtitle (optional)**

Secondary heading text. Appears below the title in post/page templates.

**status (required, default: draft)**
Controls visibility:
- draft = Not visible on public site. Only accessible by authenticated admin users.
- published = Live on site. Appears in feeds and collections.
- unlisted = Accessible at its URL and in collections, but excluded from feeds

**url_name (optional)**
Overrides the automatically generated URL slug. By default, the slug derives from the title or filename. Use this to create custom URLs.

### Specific to Posts
```
author: Sam Rockwell
date: 2026-03-10
post_type: article
```

**author**

The author of the post. 

**date (posts only, required for published posts)**

Controls sort order in feeds and collections. Format: YYYY-MM-DD (e.g., 2024-03-15) and is used on the site to show the published date of a post.

**type (optional, default: article)**

Categorizes posts for filtering. Common values: article, music, podcast, link, image. Arbitrary values allowed.
<mark>(in the future, there will be different styling for each post type. Music/podcast will have an audio player, etc.)</mark>

Layout Files do not use metadata. They contain only markdown content.

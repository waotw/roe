# Collections

Collections dynamically group and display content based on metadata. They can be defined in YAML config or embedded directly in Markdown content.

## Two Collection Systems

### 1. Inline Collections (in Markdown)

Embed collections anywhere in your content:

```markdown
```collection
heading: Latest Articles
source: posts
limit: 5
post_type: article
tags: tech
order: date
template: list
show_more: true
```
```

### 2. YAML Collections (site/system/defaults/collections.yml)

Define reusable collection presets for navigation and indexes.

---

## Inline Collection Syntax

### Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `heading` | string | — | Section heading text |
| `source` | `posts`, `pages`, `documentation` | from collections.yml | Content source |
| `limit` | number or `"all"` | `10` | Number of items to show |
| `post_type` | `article`, `music`, `podcast`, `image`, `all` | `all` | Filter by post type |
| `podcast` | podcast key (string) | — | Filter podcast episodes by show key (multi-podcast sites) |
| `tags` | comma-separated | — | Include tags (OR logic) |
| `exclude_tags` | comma-separated | — | Exclude tags |
| `order` | `date`, `date-asc`, `title`, `filename` | `date` | Sort order |
| `template` | `list`, `compact`, `links` | `list` | Display template |
| `show_more` | `true`, `false` | `false` | Show "show more" link |
| `show_more_text` | string | "Show more →" | Custom link text |
| `show_more_link` | string | — | Custom link URL |
| `exclude_id` | number | — | Exclude specific post by ID |

### Templates

**`list`** — Full display with title, date, excerpt:

```html
<section class="collection">
  <h2>Latest Articles</h2>
  <ul>
    <li>
      <article>
        <h3><a href="/posts/slug">Title</a></h3>
        <time datetime="2024-01-15">January 15, 2024</time>
        <p>Description excerpt...</p>
      </article>
    </li>
  </ul>
  <a href="/posts" class="show-more">Show more →</a>
</section>
```

**`compact`** — Minimal list without excerpts:

```html
<section class="collection-compact">
  <h2>Recent</h2>
  <ul>
    <li><a href="/posts/slug">Title</a> <time>Jan 15</time></li>
  </ul>
</section>
```

**`links`** — Plain links only:

```html
<section class="collection-links">
  <h2>Resources</h2>
  <ul>
    <li><a href="/posts/slug">Title</a></li>
  </ul>
</section>
```

### Examples

**By tag:**
```markdown
```collection
heading: Ruby Articles
source: posts
tags: ruby, rails
limit: 5
```
```

**Exclude tag:**
```markdown
```collection
heading: Non-Archived
source: posts
exclude_tags: archived
```
```

**By post type:**
```markdown
```collection
heading: Music
source: posts
post_type: music
limit: 10
```
```

**By podcast (multi-show sites):**
```markdown
```collection
heading: My Show Episodes
source: posts
post_type: podcast
podcast: my-show
limit: 10
```
```

**Ordered by title:**
```markdown
```collection
heading: A-Z Pages
source: pages
order: title
template: links
```
```

---

## YAML Collection Configuration

File: `site/system/defaults/collections.yml`

```yaml
default_source: posts
default_post_type: all
default_order: date
default_limit: "10"
default_template: list
items_per_page: "20"
button_template: |-
  heading: __PLACEHOLDER__
  limit: 5
  post_type: all
  template: list
```

### Default Source

The `default_source` is used when inline collections don't specify a source. This allows shorthand:

```markdown
```collection
limit: 5
tags: featured
```
```
*(Uses `posts` as source)*

### Button Template

The `button_template` defines "Show More" links for inline collections with `show_more: true`.

`__PLACEHOLDER__` in the heading is replaced with the collection's actual heading.

---

## Collections Controller Routes

The collections controller handles dynamic filtering via URL:

| URL | Description |
|-----|-------------|
| `/posts` | All posts archive |
| `/collections` | Base collections page |
| `/collections/tag-{tag}` | Filter by single tag |
| `/collections/{tag1},{tag2}` | Filter by multiple tags (OR) |
| `/collections/type-{post_type}` | Filter by post type |
| `/collections/{filter}/page-{n}` | Pagination |
| `/collections/{filter}/{template}` | Custom template |

### Examples

```
/collections/ruby,rails           → Posts tagged "ruby" OR "rails"
/collections/type-music           → Posts with post_type: music
/collections/ruby/page-2         → Page 2 of ruby posts
/collections/tech/compact        → Tech posts using compact template
```

---

## Processing Pipeline

When content is rendered:

1. `HasMarkdownExtensions#to_html` processes Markdown
2. Inline collections are detected via regex
3. `CollectionRenderer` fetches matching records
4. Results are filtered by tags, post_type, etc.
5. Template applied to generate HTML
6. Collections are wrapped in grid sections if consecutive

### Consecutive Collections

When two or more collections appear consecutively, they're grouped into a grid:

```markdown
```collection
heading: Featured
...
```

```collection
heading: Recent
...
```
```

Renders as a 2-column grid layout.

---

## Related

- [Content System](./02-content-system.md) - Frontmatter and status
- [Markdown Extensions](./04-markdown-extensions.md) - Other Markdown features
- [Static Generation](./05-sync-generation.md) - How collections are pre-rendered

# Extending Roe

This guide covers adding new features to Roe. Key principle: **changes often need to be made in multiple places** to work correctly with both dynamic rendering and static generation.

## Adding a New Card Type

Cards are rendered in `HasMarkdownExtensions` and pre-rendered in `StaticGenerator`. Both must be updated.

### 1. Add Renderer in HasMarkdownExtensions

File: `app/models/concerns/has_markdown_extensions.rb`

Add a method for your card type:

```ruby
def render_callout(card_config)
  text = card_config['text'] || ''
  style = card_config['style'] || 'info'
  
  <<~HTML
    <aside class="callout callout--#{style}">
      <p>#{text}</p>
    </aside>
  HTML
end
```

### 2. Update Card Router

In the same file, add to the case statement in `render_card`:

```ruby
case card_type
when 'pullquote'
  render_pullquote(card_config)
when 'aside'
  render_aside(card_config)
when 'post-link'
  render_post_link(card_config)
when 'callout'  # NEW
  render_callout(card_config)
end
```

### 3. Add Defaults (Optional)

File: `site/system/defaults/cards.yml`

```yaml
callout:
  default_style: info
```

### 4. Update Static Generator

File: `app/services/static_generator.rb`

Update the `generate_card_partial` method (around line 650):

```ruby
def generate_card_partial(card_config, local_assigns)
  card_type = card_config['type']
  
  case card_type
  when 'pullquote'
    # existing...
  when 'callout'  # NEW
    generate_callout(card_config, local_assigns)
  end
end

def generate_callout(card_config, local_assigns)
  text = card_config['text'] || ''
  style = card_config['style'] || 'info'
  
  <<~HTML
    <aside class="callout callout--#{style}">
      <p>#{text}</p>
    </aside>
  HTML
end
```

---

## Adding a New Markdown Extension

Markdown extensions are processed in `to_html`. Add new processors in the pipeline.

### 1. Add Processor Method

In `HasMarkdownExtensions`, add a method to process your extension:

```ruby
def process_spoilers(content)
  content.gsub(/\|\|(.+?)\|\|/) do
    <<~HTML
      <details class="spoiler">
        <summary>Spoiler</summary>
        <p>#{Regexp.last_match(1)}</p>
      </details>
    HTML
  end
end
```

### 2. Add to Pipeline

Update the `to_html` method to include your processor:

```ruby
def to_html
  # ... existing protection steps ...
  
  # Add your processor after appropriate step
  @content = process_spoilers(@content)
  
  # ... rest of pipeline ...
end
```

### 3. Update Static Generator (If Needed)

If your extension needs special handling during static generation, update `StaticGenerator` accordingly.

---

## Adding a New Content Type

### 1. Create Model

File: `app/models/article.rb`

```ruby
class Article < ApplicationRecord
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes
  
  scope :public_articles, -> { published }
end
```

### 2. Add to ContentSync

File: `app/services/content_sync.rb`

```ruby
def sync_articles
  directory = Rails.root.join('site', 'articles')
  return unless directory.exist?
  
  current_files = []
  
  directory.glob('**/*.md').each do |file|
    current_files << file.to_s
    sync_single_file(file)
  end
  
  handle_orphaned_records(Article, current_files)
end
```

Call `sync_articles` in `sync_all`:

```ruby
def sync_all
  # ... existing syncs ...
  sync_articles
end
```

### 3. Add Controller

File: `app/controllers/articles_controller.rb`

### 4. Add Routes

File: `config/routes.rb`

```ruby
resources :articles, only: [:show]
```

### 5. Add Views

Directory: `app/views/articles/`

### 6. Update Static Generator

File: `app/services/static_generator.rb`

Add to `generate_all`:

```ruby
generate_articles
```

Add generation methods:

```ruby
def generate_articles
  Article.published.find_each do |article|
    # Generate article page
  end
end
```

---

## Adding a New Collection Template

### 1. Add Template Method

File: `app/services/collection_renderer.rb`

```ruby
def render_badge(items)
  items.map do |item|
    <<~HTML
      <span class="badge">
        <a href="#{item.url}">#{item.title}</a>
      </span>
    HTML
  end.join
end
```

### 2. Update Template Router

In `render_collection`:

```ruby
template = config['template'] || 'list'

html = case template
when 'list'
  render_list(items, config)
when 'compact'
  render_compact(items, config)
when 'links'
  render_links(items, config)
when 'badge'  # NEW
  render_badge(items)
end
```

### 3. Add Styles

Add CSS for `.collection-badge` in your theme styles.

### 4. Update Static Generator (If Needed)

If templates need special handling during static generation.

---

## Adding to site.yml Schema

### 1. Update Config Schema

File: `app/controllers/admin/configs_controller.rb`

Add to the config schema (around line 40):

```ruby
config_schema = {
  # ... existing fields ...
  new_field: {
    type: 'text',
    label: 'New Field',
    section: 'basic'
  }
}
```

### 2. Update Form View

File: `app/views/admin/configs/_site_form.html.erb`

Add form field for the new config.

---

## File Locations Summary

| What You're Adding | Files to Update |
|--------------------|-----------------|
| New card type | `HasMarkdownExtensions`, `StaticGenerator`, `cards.yml` |
| New Markdown extension | `HasMarkdownExtensions` |
| New content type | Model, Controller, Routes, Views, `ContentSync`, `StaticGenerator` |
| New collection template | `CollectionRenderer`, CSS |
| New config field | Config controller, form view, `site.yml` |

---

## Testing Your Changes

After adding features:

1. **Dynamic rendering**: Create content using your new feature, verify in browser
2. **Static generation**: Run `rails static_site:generate`, verify output in `public/`
3. **Admin UI**: Test creation/editing through admin interface
4. **File sync**: Add content via file system, verify sync works

---

## Related

- [Architecture](./01-architecture.md) - System overview
- [Markdown Extensions](./04-markdown-extensions.md) - Existing extensions
- [Collections](./03-collections.md) - Collection system
- [Sync & Generation](./05-sync-generation.md) - Static generation process
- [Testing](./19-testing.md) - Testing your extensions
- [Troubleshooting](./18-troubleshooting.md) - Debugging issues

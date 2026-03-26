# Markdown Extensions

Roe extends standard Markdown with custom syntax for galleries, cards, and pullquotes. All processing happens in `HasMarkdownExtensions#to_html` (`app/models/concerns/has_markdown_extensions.rb`).

## Processing Pipeline

```
Raw Markdown
    ↓
1. Protect Code Blocks (`````` and ```)
    ↓
2. Protect || Pullquote Splits
    ↓
3. Process Auto-Galleries (consecutive images)
    ↓
4. Process Galleries (```gallery```)
    ↓
5. Process Collections (```collection```)
    ↓
6. Process Cards (```card```)
    ↓
7. Process Inline Footnotes
    ↓
8. Restore Code Blocks
    ↓
9. Kramdown GFM Conversion
    ↓
10. Restore Pullquote Splits
    ↓
11. CollectionGridProcessor (group consecutive)
    ↓
12. merge_floated_pullquotes
    ↓
HTML Output
```

---

## Galleries

Galleries display multiple images in a responsive grid.

### Manual Gallery

```markdown
```gallery
![Alt text](image1.jpg)
![Alt text](image2.jpg)
![Alt text](image3.jpg)
```
```

### Auto-Gallery (Consecutive Images)

Images without other content between them are automatically grouped:

```markdown
![Image one](photo1.jpg)
![Image two](photo2.jpg)

Some text breaks the gallery.

![Image three](photo3.jpg)
```

### Gallery with Captions

Use footnote syntax `(*caption*)` after an image:

```markdown
```gallery
![Mountain landscape](mountain.jpg)(*The view from the summit*)
![Ocean sunset](ocean.jpg)(*Golden hour*)
```
```

### Gallery Output

```html
<figure class="gallery">
  <div class="gallery-grid">
    <figure class="gallery-item">
      <img src="image1.jpg" alt="Alt text">
      <figcaption>The view from the summit</figcaption>
    </figure>
    <figure class="gallery-item">
      <img src="image2.jpg" alt="Alt text">
      <figcaption>Golden hour</figcaption>
    </figure>
  </div>
</figure>
```

---

## Cards

Cards are special content blocks like pullquotes, asides, and post links. The card system has defaults defined in `site/system/defaults/cards.yml`.

### Pullquote

```markdown
```card
type: pullquote
text: "The only way to do great work is to love what you do."
attribution: Steve Jobs
position: center
```
```

**Position values:** `left`, `right`, `center` (default)

**Output (center):**
```html
<blockquote class="pullquote">
  <p>The only way to do great work is to love what you do.</p>
  <cite>Steve Jobs</cite>
</blockquote>
```

**Output (left/right):**
```html
<p class="pullquote-wrapper">
  <aside class="pullquote pullquote--left">...</aside>
  Rest of paragraph content...
</p>
```

### Aside

```markdown
```card
type: aside
text: "Supplementary information here"
link: /related-page
link_text: "Learn more"
```
```

**Output:**
```html
<aside class="aside">
  <p>Supplementary information here</p>
  <a href="/related-page">Learn more →</a>
</aside>
```

### Post Link

Link to another post with optional overrides:

```markdown
```card
type: post-link
post: url-slug-of-post
style: small
image: /custom-image.jpg
```
```

**Styles:** `small` (default), `large`

**Output:**
```html
<a href="/posts/url-slug" class="post-link post-link--small">
  <img src="/media/images/default.jpg" alt="">
  <span class="post-link-title">Post Title</span>
  <span class="post-link-text">Read full story →</span>
</a>
```

### Card Defaults

File: `site/system/defaults/cards.yml`

```yaml
post-link:
  default_image: /media/images/default.jpg
  default_style: small
  default_link_text: "Read full story →"
aside:
  default_link_text: "→"
pullquote:
  default_position: center
```

Field values in the card override these defaults.

---

## Pullquote Splits

Create side-by-side layouts by splitting paragraphs with `||`:

```markdown
||This text becomes an aside.||
```

Or use a card with position:

```markdown
```card
type: pullquote
text: "Floated pullquote"
position: right
```
```

### Smart Splitting

Without explicit `||` markers, the system finds natural sentence breaks:

1. Checks for sentences ending with `?` or `!`
2. Falls back to longest sentence ending with `.`
3. Wraps the split paragraph with the pullquote

---

## Code Block Protection

Code blocks are protected from Markdown processing using a placeholder system.

```markdown
```ruby
def hello
  puts "World"
end
```

```collection
...this won't be processed...
```
```

The system:
1. Extracts code blocks to placeholders before processing
2. Restores them after Kramdown conversion

**Supported fences:** `` ``` `` (3+) and `` ``` `` (4+ backticks)

---

## Extension Order Matters

The processing order means:

1. **Galleries are processed before collections** — images inside collection blocks won't auto-gallery
2. **Cards are processed after collections** — cards inside collection content are processed
3. **Code blocks are protected first and restored last** — ensures syntax isn't misinterpreted

---

## Adding New Extensions

See [Extending](./09-extending.md) for how to add new card types or Markdown processors.

---

## Related

- [Collections](./03-collections.md) - Inline collection syntax
- [Extending](./09-extending.md) - Adding new extensions
- [Static Generation](./05-sync-generation.md) - How extensions are processed during static build

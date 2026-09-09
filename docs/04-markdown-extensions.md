# Markdown Extensions

Roe extends standard Markdown with custom syntax for galleries, cards, collections, forms, and buttons. All processing happens in `HasMarkdownExtensions#to_html` (`app/models/concerns/has_markdown_extensions.rb`).

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

## Forms & Buttons

Two block types add interactive elements, both selected by `for:` (preferred) or `type:` (alias) via `roeanji_kind` — `for` wins on conflict, and a mismatch dev-warns through `roeanji_kind_conflict_warning`.

### Buttons (` ```button `)

A bare `button` block is a **product** button (`ProductButtonRenderer`). `for:`/`type:` switches the kind; non-product kinds dispatch through `render_action_button`:

| `for:` | Renderer | Output |
|--------|----------|--------|
| *(none)* / `product` | `ProductButtonRenderer` | Snipcart add-to-cart button |
| `share` | `render_share_button` | `data-controller="share"` trigger + `.button-menu` (Copy link / Email); native share sheet on touch |
| `subscribe` | `render_members_button` | `<a class="btn-primary">` → `/sign-up`, gated on `SiteFeature.members_enabled?` |

`style:` tokens become sanitised modifier classes via `action_button_style_classes(config, prefix)` (`share-<token>`, `members-<token>`). Unrecognised kinds dev-warn.

### Forms (` ```form `)

`for:` selects the flow — `signup`, `signin`, `checkout`, `donate`, `unsubscribe`, `paid_content` — each rendering the matching membership/payment partial. Default button labels come from `default_button_text` and are overridable (`button-text:` etc.).

Full option tables live in the user docs (`site/documentation/roe/roeanji_forms-and-buttons.md`).

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

Two things about the restore step in `HasMarkdownExtensions#to_html` that look
like fussiness and aren't:

- **The wrapping paragraph is replaced along with the token.** Kramdown wraps a
  bare placeholder in `<p>`, and `<pre>` can't legally sit inside `<p>` — so
  replacing only the token yields `<p><pre>…</pre></p>`, which the next Nokogiri
  pass rewrites to `<p></p><pre>…</pre>`. That left a stray empty paragraph
  before every code block on the site. A second pass over the bare token still
  runs afterwards, because Kramdown doesn't wrap every placement (a fence inside
  a list item, for example) and those must still restore.
- **`gsub` is used in its block form.** With a string replacement, Ruby reads
  `\0`, `\1` and `\\` in the *replacement* as backreferences. The pattern has no
  capture groups, so a code block containing `\1` had it silently deleted —
  which bit regex examples, `sed` one-liners, and Windows paths.

---

## Footnotes

Standard Kramdown footnotes (`[^name]` / `[^name]:`). The older `(*…*)` inline
syntax is retired; `HasInlineFootnotes` is a no-op kept so existing `include`
statements don't need changing. `(*caption*)` after an image is a separate
feature — see [Gallery with Captions](#gallery-with-captions).

Roe renders with `footnote_backlink: ""` and `footnote_backlinks_inline: true`,
then `add_footnote_backlinks` prepends a numbered backlink to each note.

### Known quirks

**Numbers follow the first *reference*, not the definition order.** Definitions
can sit anywhere in the file — Kramdown collects them and renders the list at
the end regardless.

**Kramdown puts the reference id on the `<sup>`, not the `<a>`:**

```html
<sup id="fnref:name"><a href="#fn:name" class="footnote">1</a></sup>
```

Anything walking from a reference back to its anchor has to read the parent.
This is not obvious from the rendered page and has cost debugging time more than
once — both `add_footnote_backlinks` and `site_js/footnotes.js` handle it, with
the anchor as a fallback.

**Backlink numbering counts only the footnote list's own items.** The selector is
`.footnotes > ol > li`, not `.footnotes ol > li`. The latter also matches the
items of an ordered list *inside* a footnote — those are direct children of *an*
`ol` that descends from `.footnotes` — so a note containing a numbered list was
counted as several notes and everything after it drifted. `<ul>` never triggered
it, which is why an earlier partial fix looked complete.

**A note referenced more than once gets a return link per mention.** The leading
number can only point at one of them, so on its own it always returns you to the
first. Kramdown ids repeat references `fnref:name`, `fnref:name:1`, … and each
gets a `.footnote-return` link. These are plain anchors and work with no
JavaScript. `site_js/footnotes.js` then enhances it: clicking a reference
repoints that note's leading number at the mention you came from. Single-reference
notes are untouched — no extra markup at all.

**Notes ending in a block carry an empty `<p>`.** With
`footnote_backlinks_inline`, Kramdown appends the backlink to the note's last
paragraph; when the note ends in a quote, list, code block, table, or image it
adds a paragraph to hold it, and since `footnote_backlink` is `""` that
paragraph arrives empty.

This is *not* the code-block placeholder issue above — different cause, same
symptom. It's left alone deliberately: the themes hide it with
`.content p:empty { display: none }`, and removing it would shift spacing on
every block-ending footnote in every existing post. Return links fill the slot
when a note has them, which is why `.footnote-returns` is inserted into that
paragraph rather than appended to the `<li>`.

`site/posts/footnote-test.md` exercises all of the above if you need a page to
look at.

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

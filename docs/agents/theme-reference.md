# Theme reference pages

Admin-only pages that show every element a theme styles, drawn in the site's
own layout. They're the reference for theme work, the before-and-after check
for the theme clean-up, and the page the theme editor's preview opens on.

## Where things are

| What | Where |
| --- | --- |
| Page list, sample-content insert, media path | `app/services/theme_reference.rb` |
| The pages, as Markdown | `app/views/admin/theme_reference/pages/*.md` |
| Sample posts and products | `app/views/admin/theme_reference/sample_content.yml` |
| Sample images, audio, video (about 550 KB) | `app/views/admin/theme_reference/media/` |
| Page and bar | `Admin::ThemeReferenceController`, `admin/theme_reference/show.html.erb` |
| Media, with byte ranges | `Admin::ThemeReferenceMediaController` (subclass of `MediaController`) |
| Routes | `/admin/themes/reference(/:page)`, `/admin/themes/reference/media/:path` |
| Tests | `test/controllers/admin/theme_reference_test.rb` |

## Decisions

- **Everything lives in `current/`, never `site/`.** The pages are Roe's
  admin, not the site's content: every install has them, they match the Roe
  that runs them, and nothing reaches Site Sync, the static site, search or
  the sitemap. The cost is that a site can't edit them. A later option is to
  ship the samples as a separate download.
- **Rendered by the real pipeline.** Each page is an unsaved `Page` carrying
  the Markdown, drawn through `render_content_layout` in the `site` layout,
  so the site's `page.txt`, header, sidebar and footer all apply.
- **Sample content is inserted and rolled back for each render.**
  Collections, post links, product links, product grids and buy buttons read
  from the database, and overriding each lookup would drift from the real
  code. `ThemeReference.with_sample_content` inserts the rows with
  `insert_all` (no callbacks: `Product#register_category` writes
  `store.yml`) inside `transaction(requires_new: true)`, renders, then raises
  `ActiveRecord::Rollback`. Other connections never see uncommitted rows.
  Every sample `url_name` starts with `theme-reference-`, and the page's
  script stops clicks on links to them, since they 404 afterwards.
- **Features answer as on for the render.** Forms and buttons for members,
  payments and the store draw even when the site has them off, so a theme can
  be styled first. `SiteFeature.showing_everything { }` sets a thread-local
  flag that `members_enabled?`, `store_enabled?`, `snipcart_enabled?`,
  `payments_feature_enabled?`, `payments_enabled?`,
  `memberships_configured?` and `payments_mode` ("both") check first. Per
  thread, reset in `ensure`. Hiding these pages when a feature is off was
  considered and deferred.
- **The paywall shows as a visitor sees it.** Admins normally see paid content
  with the gate removed (`PagesHelper#should_truncate_content?`). The
  controller overrides that helper so the Forms & Members page keeps it.
- **Theme choice reuses `?preview_theme=`.** The site layout already loads
  that theme's CSS and marks the page noindex. The controller only accepts a
  theme installed in `site/theme/`; anything else redirects to the page
  without it.
- **The bar is fixed, not in the page's flow.** A theme with a sidebar lays
  `body` out as a grid, and an extra child of `body` would take a cell. The
  bar is `position: fixed`, `html` gets padding and `scroll-padding-top` of
  the bar's height (kept current by a `ResizeObserver`), and `.site-actions`
  moves down with `translate`. Its styles sit under an id with
  `all: revert`, so theme rules don't reach it. It goes in through
  `yield :admin_bar` at the top of `layouts/site.html.erb`.
- **Forms don't submit and buy buttons don't add to the cart.** One capture
  listener on `window` for each.

## Keeping it complete

The test "every Roe-anji block has an example on a reference page" reads the
builder schemas (`CardBuilderSchema::TYPES`, the collection `template`
options plus `grid`, `GalleryBuilderSchema::DIRECTIVES`,
`ActionBuilderSchema::FORM_KINDS` and `BUTTON_KINDS`) and fails when one has
no example. Add the example to the matching page when it fails.

Another test renders every page in every theme in `app/themes/` with block
warnings on and fails on any warning.

## Traps

- **Two kinds of theme change, checked two ways.** A change that should
  look identical (reorganising, renaming, moving rules) gets a comparison
  of computed styles, not screenshots. Every element's box and about 140
  computed properties are recorded on every reference page in each shipped
  theme at 1280 and 390 px wide, before and after. The heading and reorder
  passes on 1.6.13 / 1.5.13 were checked this way:
  - 36 reference pages;
  - 52 real pages (home, docs, store, product, post, member pages), with the
    old file installed as `zz-before-<theme>.css` and shown through
    `?preview_theme=`;
  - 24 pages in dark mode.

  All were identical. A change meant to look different gets before and after
  screenshots for a person to judge.
- The shipped themes' section headings and order are fixed by
  `test/services/theme_sections_test.rb`; `ThemeSections.parse` is the
  parser the editor's section list will use. THEME INFO is the one heading
  that runs over several lines, because it is also the header comment the
  update system reads (`ShippedFileInspector`), and that has to stay a
  single comment.
- Sample images are `loading="lazy"`. Full-page screenshots need
  `img.loading = "eager"` first, or most images come out blank.
- `(*caption*)` image captions can't contain `*`, so no bold inside them.
- A `menu` collection needs an `order:` list or a `collection:` name, or it
  draws a warning instead of links.
- `fold:` only applies to the `playlist` template.
- The recovery (password reset) form draws only on a site that uses
  passwords, so it isn't on the Forms page.

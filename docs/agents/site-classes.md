# Site CSS classes

The classes Roe's public site emits, which shipped themes style them, and
which have shipped. Custom themes target these, so a shipped class never
changes: see [conventions.md](conventions.md) §9.

## How this was made

Taken on 2026-11-15, during 0.5.0 development, as a one-off. It is not generated
and will drift, so re-check any row before relying on it.

- **Pages:** every public page crawled signed out, plus the theme reference pages
  and paid posts signed in, recording each class on the rendered page after
  the site JS ran.
- **Source:** the public views, helpers, Markdown extensions, content layout
  parts, site JS and the two Stimulus controllers that run on public pages, for
  markup only some states show (member account, search results, checkout).
- **Shipped:** whether the class is in v0.4.1's public source or themes.
  "pattern" means it's built from a value: `page-<url_name>`, `post-<post_type>`,
  `sidebar-<position>`, `flash-<type>`, `gallery-ratio-<v>`, `img-<ratio>`,
  `logo-<style>`, `share-<style>`, `language-<lang>`.
- **Left out:** the admin sign-in and password screens, which use Tailwind.

## Changes in 0.5.0 (for the release notes)

Custom themes may need updating for these.


- **Removed:** the old podcast player and episode list (`a972d27`): `audio-player`, `player-header`,
  `player-artwork`, `player-info`, `player-title`, `player-ui`,
  `player-controls`, `player-btn`, `now-playing`, `current-time`,
  `progress-fill`, `progress-handle`, `controls-center`, `btn-play`, `btn-prev`,
  `btn-next`, `btn-skip`, `btn-speed`, `btn-wrapper`, `btn-episode`,
  `btn-episode-nav`, `episode-meta`, `episode-nav-title`, `chapters-heading`,
  `is-disabled`, `podcast-hero`, `hero-player`, `episode-list`, `episode-item`,
  `episode-meta-row`, `episode-number`, `episode-duration`, `episode-date`. The
  new player's markup is different, so there's nothing to alias them to. They
  belong in the 0.5.0 release notes.
- **Moved:** on documentation pages `.documentation` moved from the `<article>` to the
  `<div class="content">` inside it (`article.documentation-page`). `.content.documentation` still matches;
  `article.documentation` doesn't.
- **Writing wrapped:** a page's and a doc's writing now sit in `.page-content` /
  `.documentation-content` inside `.content`, so `.content > p` no longer
  reaches it.
- **Dropped from the shipped themes:** six selectors that nothing emits, in
  default 1.6.16 and bare 1.5.16: `card-body`, `collection-heading`,
  `password-display`, `password-note`, `alert--success`, `aside-link-inline`.
- **Page names:** `page-<url_name>` shares its prefix with content layout part classes
  (`page-image`, `page-tags`). A page named like a part gets no name class
  (`Page#name_class`), and the page editor says so.
- **Field classes:** metadata fields drawn by a layout are `<kind>-field
  <kind>-field-<name>`. They were briefly `<kind>-<name>` during development, so a
  field called `header` would have been `post-header`.

## Shipped names that break the pattern, kept on purpose

| Area | Names |
|---|---|
| List items | `item-*` (collections), `card-*` (cards), `grid-item-*` (product grid) |
| Meta | `post-meta`, `item-meta`, but `card-metadata` |
| Headings | `collection-page-heading`, next to `podcast-page-title` and `release-page-title` |
| Buttons | `btn-*` and `*-button`, `video-btn`, `button-menu`, `button` (Substack imports) |
| Modifiers | `alert--error`, `site-search--open`, `site-search-result-link--active`, `podcast-subscribe--menu`; bare words on `.collection` (`compact`, `full`, `list`, `links`, `menu`, `grid`, `playlist`) |
| States | `active` (menu), `is-current`, `is-active`, `is-selected`, `variant-current`, `breadcrumb-current`; the player has both `is-playing` on its root and `data-playing` on its button |
| Containers | plurals (`player-tracks`, `footnotes`) and `-list` (`chapter-list`, `glossary-list`) |
| Underscores | `logo-beside_text`, `logo-replace_text` (setting values), and `page-<url_name>` keeps underscores |
| Two players | audio `player-*`; video `video-*`, `btn-play-pause`, `btn-fullscreen`, `icon-*` |
| Card sizes | `post-link-large/medium/small`, `product-link-*` (named after the old `[post-link]`) |
| Tailwind | `w-5 h-5` on the heading-anchor icon; `ha-icon` is the site's own class for it |

## Every class

`Pages seen` counts crawled pages. 0 means it only appears in some states, or only in
the source. "new" means not in v0.4.1.

| Class | Shipped | Emitted from | default | bare | Pages seen | Example |
| `account-actions` | 0.4.1 | `app/views/members/accounts/show.html.erb:172` | ✓ | ✓ | 0 |  |
| `account-delete` | 0.4.1 | `app/views/members/accounts/show.html.erb:153` | ✓ | ✓ | 0 |  |
| `account-delete-button` | 0.4.1 | `app/views/members/accounts/show.html.erb:168` |  |  | 0 |  |
| `account-delete-form` | 0.4.1 | `app/views/members/accounts/show.html.erb:164` | ✓ | ✓ | 0 |  |
| `account-delete-input` | 0.4.1 | `app/views/members/accounts/show.html.erb:167` | ✓ | ✓ | 0 |  |
| `account-details` | 0.4.1 | `app/views/members/accounts/show.html.erb:4` | ✓ | ✓ | 0 |  |
| `account-newsletter` | 0.4.1 | `app/views/members/accounts/show.html.erb:60` |  |  | 0 |  |
| `account-newsletter-form` | 0.4.1 | `app/views/members/accounts/show.html.erb:66` |  |  | 0 |  |
| `account-newsletter-note` | 0.4.1 | `app/views/members/accounts/show.html.erb:63` |  |  | 0 |  |
| `account-password` | 0.4.1 | `app/views/members/accounts/show.html.erb:91` |  |  | 0 |  |
| `account-password-form` | 0.4.1 | `app/views/members/accounts/show.html.erb:93` |  |  | 0 |  |
| `account-recovery` | 0.4.1 | `app/views/members/accounts/show.html.erb:110` |  |  | 0 |  |
| `account-recovery-codes` | 0.4.1 | `app/views/members/accounts/show.html.erb:122` | ✓ |  | 0 |  |
| `account-recovery-form` | 0.4.1 | `app/views/members/accounts/show.html.erb:143` |  |  | 0 |  |
| `account-recovery-note` | 0.4.1 | `app/views/members/accounts/show.html.erb:114` |  |  | 0 |  |
| `active` | 0.4.1 | `app/helpers/application_helper.rb:87` | ✓ | ✓ | 4 | / |
| `alert` | 0.4.1 | `app/views/checkout/cancel.html.erb:2` | ✓ | ✓ | 0 |  |
| `alert--error` | 0.4.1 | `app/views/checkout/payment_processing.html.erb:28` | ✓ | ✓ | 0 |  |
| `alert--info` | 0.4.1 | `app/views/checkout/payment_processing.html.erb:8` | ✓ | ✓ | 0 |  |
| `alert--warning` | 0.4.1 | `app/views/donations/cancel.html.erb:2` | ✓ | ✓ | 0 |  |
| `alert-note` | 0.4.1 | `app/views/checkout/payment_processing.html.erb:11` | ✓ | ✓ | 0 |  |
| `aside-body` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3494` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `aside-image` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3491` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `aside-image-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3492` | ✓ | ✓ | 0 |  |
| `aside-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3477` | ✓ | ✓ | 3 | /lab-kitchen-sink |
| `aside-text` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3471` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `aside-wrapper` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3501` | ✓ | ✓ | 3 | /admin/themes/reference/cards |
| `audio-embed` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:175` |  |  | 1 | /admin/themes/reference/media |
| `back-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1263` | ✓ | ✓ | 0 |  |
| `breadcrumb-current` | 0.4.1 | `app/helpers/application_helper.rb:245` | ✓ | ✓ | 8 | /store/lab-poster |
| `breadcrumb-link` | 0.4.1 | `app/helpers/application_helper.rb:222` | ✓ | ✓ | 8 | /store/lab-poster |
| `breadcrumb-text` | 0.4.1 | `app/helpers/application_helper.rb:229` | ✓ | ✓ | 8 | /store/lab-poster |
| `breadcrumbs` | 0.4.1 | `app/helpers/application_helper.rb:217` | ✓ | ✓ | 8 | /store/lab-poster |
| `btn-destructive` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3729` | ✓ | ✓ | 3 | /admin/themes/reference/forms |
| `btn-fullscreen` | 0.4.1 | `app/views/shared/_video_player.html.erb:66` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `btn-grid` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2453` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `btn-outline` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3899` | ✓ | ✓ | 9 | /admin/themes/reference/buttons |
| `btn-play-pause` | 0.4.1 | `app/views/shared/_video_player.html.erb:52` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `btn-primary` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2453` | ✓ | ✓ | 19 | /admin/themes/reference/buttons |
| `btn-secondary` | 0.4.1 | `app/views/checkout/cancel.html.erb:19` | ✓ | ✓ | 1 | /admin/themes/reference/buttons |
| `button` | 0.4.1 | `app/services/substack_importer/converter.rb:579` |  |  | 0 |  |
| `button-menu` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4284` | ✓ | ✓ | 5 | /admin/themes/reference/buttons |
| `card` | 0.4.1 | `app/helpers/image_variant_helper.rb:13` | ✓ | ✓ | 10 | /admin/themes/reference/cards |
| `card-aside` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3458` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `card-author` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:22` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `card-content` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4085` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `card-date` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:24` |  |  | 4 | /admin/themes/reference/cards |
| `card-excerpt` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:37` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `card-header` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:7` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `card-image` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:31` | ✓ | ✓ | 6 | /admin/themes/reference/cards |
| `card-link` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:39` | ✓ | ✓ | 6 | /admin/themes/reference/cards |
| `card-metadata` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:21` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `card-player` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2064` | ✓ | ✓ | 20 | /admin/themes/reference/players |
| `card-player-plain` | new | `app/models/concerns/has_markdown_extensions.rb:2089` |  |  | 0 |  |
| `card-player-video` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2064` | ✓ |  | 5 | /admin/themes/reference/players |
| `card-price` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:10` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `card-pullquote` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2966` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `card-subtitle` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:17` | ✓ | ✓ | 0 |  |
| `card-title` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:8` | ✓ | ✓ | 6 | /admin/themes/reference/cards |
| `chapter` | 0.4.1 | `app/helpers/posts_helper.rb:3` | ✓ | ✓ | 0 |  |
| `chapter-list` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2198` | ✓ | ✓ | 0 |  |
| `chapter-time` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2194` | ✓ | ✓ | 0 |  |
| `chapter-title` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2195` | ✓ | ✓ | 0 |  |
| `checkout-form` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4033` |  |  | 3 | /admin/themes/reference/forms |
| `checkout-form-wrapper` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4041` | ✓ | ✓ | 2 | /admin/themes/reference/forms |
| `checkout-loading-message` | 0.4.1 | `app/site_js/checkout.js` |  |  | 0 |  |
| `checkout-loading-overlay` | 0.4.1 | `app/site_js/checkout.js` |  |  | 0 |  |
| `clear-floats` | 0.4.1 | `app/helpers/products_helper.rb:14` | ✓ | ✓ | 0 |  |
| `collection` | 0.4.1 | `app/helpers/layout_helper.rb:10` | ✓ | ✓ | 118 | / |
| `collection-context` | 0.4.1 | `app/helpers/seo_helper.rb:318` |  |  | 0 |  |
| `collection-description` | 0.4.1 | `app/views/collections/show.html.erb:4` | ✓ | ✓ | 2 | /collections |
| `collection-grid` | 0.4.1 | `app/services/collection_grid_processor.rb:65` | ✓ | ✓ | 4 | / |
| `collection-grid-2` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 2 | / |
| `collection-grid-3` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 2 | /documentation-all |
| `collection-header` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1070` | ✓ | ✓ | 3 | / |
| `collection-item` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:145` | ✓ | ✓ | 29 | / |
| `collection-menu` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1899` | ✓ | ✓ | 118 | / |
| `collection-menu-horizontal` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 118 | / |
| `collection-menu-item` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1883` | ✓ | ✓ | 118 | / |
| `collection-menu-vertical` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 48 | / |
| `collection-more` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1433` | ✓ | ✓ | 4 | / |
| `collection-nav` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1909` |  |  | 118 | / |
| `collection-page` | 0.4.1 | `app/views/collections/show.html.erb:1` |  |  | 2 | /collections |
| `collection-page-heading` | 0.4.1 | `app/views/collections/show.html.erb:2` | ✓ | ✓ | 2 | /collections |
| `compact` | 0.4.1 | `app/helpers/seo_helper.rb:99` | ✓ | ✓ | 3 | /admin/themes/reference/collections |
| `content` | 0.4.1 | `app/helpers/application_helper.rb:6` | ✓ | ✓ | 117 | / |
| `detail-row` | 0.4.1 | `app/views/members/accounts/show.html.erb:10` |  |  | 0 |  |
| `docs-back-link` | 0.4.1 | `app/views/documentation/show.html.erb:1` | ✓ | ✓ | 15 | /documentation/roe/about-file-first-approach |
| `docs-bundled-note` | 0.4.1 | `app/views/documentation/show.html.erb:5` |  |  | 0 |  |
| `documentation` | 0.4.1 | `app/helpers/admin_helper.rb:12` | ✓ | ✓ | 15 | /documentation/roe/about-file-first-approach |
| `documentation-content` | new | `app/views/content_layouts/parts/_body.html.erb:4` | ✓ | ✓ | 15 | /documentation/roe/about-file-first-approach |
| `documentation-page` | new | `app/models/content_layout/explain.rb:188` |  |  | 15 | /documentation/roe/about-file-first-approach |
| `donate-form` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3684` |  |  | 1 | /admin/themes/reference/forms |
| `donate-presets` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3705` | ✓ | ✓ | 1 | /admin/themes/reference/forms |
| `duration` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2283` |  |  | 0 |  |
| `error-page` | 0.4.1 | `app/views/errors/not_found.html.erb:1` |  |  | 0 |  |
| `feed-link` | 0.4.1 | `app/models/content_layout/explain.rb:210` | ✓ | ✓ | 36 | /podcast |
| `feed-link-app` | 0.4.1 | `app/views/content_layouts/parts/_subscribe.html.erb:49` |  |  | 7 | /posts/03-where-s-my-party |
| `feed-link-private` | 0.4.1 | `app/views/content_layouts/parts/_feed_links.html.erb:15` | ✓ | ✓ | 7 | /posts/03-where-s-my-party |
| `feed-links` | new | `app/models/content_layout/explain.rb:210` |  |  | 35 | /posts/01-my-comics-aren-t-for-kids |
| `flash` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3686` | ✓ | ✓ | 3 | /admin/themes/reference/layout |
| `flash-alert` | 0.4.1 (pattern) | `app/views/layouts/site.html.erb:113` |  |  | 3 | /admin/themes/reference/layout |
| `flash-notice` | 0.4.1 (pattern) | `app/views/layouts/site.html.erb:113` |  |  | 1 | /admin/themes/reference/layout |
| `footnote` | 0.4.1 | `app/models/concerns/has_inline_footnotes.rb:6` | ✓ | ✓ | 8 | /admin/themes/reference/text |
| `footnote-backlink-number` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:525` | ✓ | ✓ | 8 | /admin/themes/reference/text |
| `footnote-return` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:568` | ✓ | ✓ | 0 |  |
| `footnote-returns` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:558` | ✓ | ✓ | 0 |  |
| `footnote-tooltip` | 0.4.1 | `app/views/layouts/site.html.erb:106` | ✓ | ✓ | 118 | / |
| `footnotes` | 0.4.1 | `app/models/concerns/has_inline_footnotes.rb:7` | ✓ | ✓ | 8 | /admin/themes/reference/text |
| `form-actions` | 0.4.1 | `app/views/checkout/cancel.html.erb:16` | ✓ | ✓ | 0 |  |
| `form-errors` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3868` | ✓ | ✓ | 0 |  |
| `form-field` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3708` | ✓ | ✓ | 5 | /admin/themes/reference/forms |
| `full` | 0.4.1 | `app/helpers/application_helper.rb:116` | ✓ | ✓ | 6 | /admin/themes/reference/collections |
| `gallery` | 0.4.1 | `app/helpers/products_helper.rb:7` | ✓ | ✓ | 13 | / |
| `gallery-caption` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:821` | ✓ | ✓ | 3 | /admin/themes/reference/media |
| `gallery-carousel` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:814` | ✓ | ✓ | 4 | /about |
| `gallery-col-1` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 2 | /admin/themes/reference/media |
| `gallery-col-2` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 5 | /admin/themes/reference/media |
| `gallery-col-3` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 11 | / |
| `gallery-dot` | 0.4.1 | `app/site_js/gallery.js:105` | ✓ | ✓ | 4 | /about |
| `gallery-dots` | 0.4.1 | `app/site_js/gallery.js:102` | ✓ | ✓ | 4 | /about |
| `gallery-figure` | 0.4.1 | `app/helpers/products_helper.rb:39` | ✓ | ✓ | 3 | /admin/themes/reference/media |
| `gallery-item` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:884` | ✓ | ✓ | 13 | / |
| `gallery-nav` | 0.4.1 | `app/site_js/gallery.js:55` | ✓ | ✓ | 4 | /about |
| `gallery-nav-button` | 0.4.1 | `app/site_js/gallery.js:92` | ✓ | ✓ | 4 | /about |
| `gallery-next` | 0.4.1 | `app/site_js/gallery.js:97` | ✓ | ✓ | 4 | /about |
| `gallery-prev` | 0.4.1 | `app/site_js/gallery.js:92` | ✓ | ✓ | 4 | /about |
| `gallery-ratio-auto` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-cinema` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-film` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-landscape` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-original` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-portrait` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-square` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 3 | /posts/galleries |
| `gallery-ratio-tv` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `gallery-ratio-wide` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 1 | /admin/themes/reference/media |
| `gallery-row` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:894` | ✓ | ✓ | 11 | / |
| `gallery-track` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:911` | ✓ | ✓ | 4 | /about |
| `gallery-zoom` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:944` | ✓ | ✓ | 13 | / |
| `gallery-zoom-close` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:945` | ✓ | ✓ | 13 | / |
| `gallery-zoom-image` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:946` | ✓ | ✓ | 13 | / |
| `gallery-zoom-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:927` | ✓ | ✓ | 13 | / |
| `glossary` | 0.4.1 | `app/models/collection_builder_schema.rb:78` | ✓ | ✓ | 1 | /admin/themes/reference/collections |
| `glossary-entry` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1818` | ✓ | ✓ | 1 | /admin/themes/reference/collections |
| `glossary-list` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1817` |  |  | 1 | /admin/themes/reference/collections |
| `grid-item` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2380` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `grid-item-description` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2419` | ✓ | ✓ | 1 | /store |
| `grid-item-footer` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2423` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `grid-item-image` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2393` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `grid-item-price` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2442` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `grid-item-title` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2405` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `grid-item-variants` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2412` | ✓ | ✓ | 3 | /admin/themes/reference/store |
| `h-5` | 0.4.1 | `app/helpers/application_helper.rb:272` |  |  | 83 | /about |
| `ha-icon` | 0.4.1 (pattern) | `(dynamic)` |  |  | 83 | /about |
| `ha-icon-copied` | 0.4.1 | `app/views/layouts/site.html.erb:62` |  |  | 83 | /about |
| `ha-icon-default` | 0.4.1 | `app/views/layouts/site.html.erb:63` |  |  | 83 | /about |
| `has-heading-anchor` | 0.4.1 | `app/views/layouts/site.html.erb:43` |  |  | 83 | /about |
| `has-sidebar` | 0.4.1 | `app/views/layouts/site.html.erb:92` | ✓ | ✓ | 48 | / |
| `heading-anchor` | 0.4.1 | `app/views/layouts/site.html.erb:44` | ✓ | ✓ | 83 | /about |
| `home` | 0.4.1 | `app/helpers/layout_helper.rb:213` | ✓ | ✓ | 0 |  |
| `icon-fullscreen` | 0.4.1 | `app/views/shared/_video_player.html.erb:69` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `icon-fullscreen-exit` | 0.4.1 | `app/views/shared/_video_player.html.erb:70` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `icon-pause` | 0.4.1 | `app/views/shared/_video_player.html.erb:56` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `icon-play` | 0.4.1 | `app/views/shared/_video_player.html.erb:55` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `image-only` | 0.4.1 | `app/models/card_builder_schema.rb:41` | ✓ | ✓ | 2 | /posts/aside-cards |
| `img-auto` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 2 | /admin/themes/reference/store |
| `img-cinema` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `img-film` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `img-landscape` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `img-original` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `img-portrait` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `img-square` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 3 | /admin/themes/reference/store |
| `img-tv` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 1 | /store |
| `img-wide` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `is-active` | 0.4.1 | `app/site_js/player.js:365` | ✓ | ✓ | 0 |  |
| `is-current` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1944` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `is-ended` | 0.4.1 | `app/site_js/player.js` |  |  | 0 |  |
| `is-enhanced` | 0.4.1 | `app/site_js/player.js:100` | ✓ | ✓ | 21 | /admin/themes/reference/media |
| `is-error` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4084` |  |  | 0 |  |
| `is-fullscreen` | 0.4.1 | `app/site_js/player.js:231` | ✓ | ✓ | 0 |  |
| `is-guest` | 0.4.1 | `app/helpers/pages_helper.rb:9` | ✓ | ✓ | 2 | /admin/themes/reference/forms |
| `is-member` | 0.4.1 | `app/helpers/pages_helper.rb:9` | ✓ | ✓ | 0 |  |
| `is-paid` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1944` | ✓ | ✓ | 10 | /podcast |
| `is-paused` | 0.4.1 | `app/site_js/player.js` |  |  | 0 |  |
| `is-paywalled` | 0.4.1 | `app/site_js/player.js` |  |  | 0 |  |
| `is-playing` | 0.4.1 | `app/site_js/player.js:304` | ✓ | ✓ | 3 | /admin/themes/reference/players |
| `is-selected` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `is-unavailable` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2488` |  |  | 0 |  |
| `item-author` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1604` | ✓ | ✓ | 6 | /blog |
| `item-body` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1646` | ✓ | ✓ | 6 | /admin/themes/reference/collections |
| `item-date` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1603` | ✓ | ✓ | 17 | / |
| `item-excerpt` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1662` | ✓ | ✓ | 5 | /admin/themes/reference/collections |
| `item-image` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1641` | ✓ | ✓ | 6 | /admin/themes/reference/collections |
| `item-meta` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1606` | ✓ | ✓ | 15 | / |
| `item-subtitle` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1594` | ✓ | ✓ | 18 | / |
| `item-title` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1420` | ✓ | ✓ | 31 | / |
| `large-card-excerpt-link` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:35` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `layout-group` | new | `app/helpers/content_layout_helper.rb:11` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `layout-row` | new | `app/helpers/content_layout_helper.rb:11` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `links` | 0.4.1 | `app/helpers/admin_helper.rb:12` | ✓ | ✓ | 14 | /admin/themes/reference/collections |
| `list` | 0.4.1 | `app/helpers/admin_helper.rb:17` | ✓ | ✓ | 11 | / |
| `loading-spinner` | 0.4.1 | `app/site_js/checkout.js` |  |  | 0 |  |
| `logo` | 0.4.1 | `app/helpers/application_helper.rb:112` | ✓ | ✓ | 118 | / |
| `logo-beside_text` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 118 | / |
| `logo-replace_text` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `member-checkout` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4042` | ✓ | ✓ | 2 | /admin/themes/reference/forms |
| `member-link` | 0.4.1 | `app/views/layouts/site.html.erb:200` | ✓ | ✓ | 0 |  |
| `member-page` | 0.4.1 | `app/models/page.rb:89` | ✓ | ✓ | 14 | /check-email |
| `members-large-subscribe` | 0.4.1 | `lib/site_templates/minimum/documentation/roe/roeanji_forms-and-buttons.md:100` |  |  | 1 | /posts/test-image-optimization |
| `menu` | 0.4.1 | `app/helpers/layout_helper.rb:16` | ✓ | ✓ | 118 | / |
| `no-image` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:5` | ✓ | ✓ | 1 | /posts/post-link-cards |
| `non-member-checkout` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4047` | ✓ | ✓ | 2 | /admin/themes/reference/forms |
| `page` | 0.4.1 | `app/helpers/admin_helper.rb:5` | ✓ | ✓ | 49 | / |
| `page-artist` | new | `app/models/content_layout/explain.rb:216` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `page-artwork` | new | `app/services/podcast_config_seeder.rb:164` |  |  | 1 | /podcast |
| `page-author` | new | `app/models/content_layout/explain.rb:208` |  |  | 2 | /podcast |
| `page-content` | new | `app/views/content_layouts/parts/_body.html.erb:3` | ✓ | ✓ | 48 | / |
| `page-cover` | new | `app/services/substack_importer/frontmatter.rb:155` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `page-creator` | new | `app/models/content_layout/explain.rb:217` |  |  | 1 | /podcast |
| `page-date` | new | `app/models/content_layout/explain.rb:207` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `page-documentation` | 0.4.1 | `app/views/documentation/index.html.erb:3` | ✓ | ✓ | 2 | /documentation |
| `page-excerpt` | new | `app/models/content_layout/explain.rb:220` | ✓ | ✓ | 0 |  |
| `page-image` | new | `app/models/content_layout/explain.rb:209` | ✓ | ✓ | 2 | /podcast |
| `page-release-date` | new | `app/models/content_layout/explain.rb:218` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `page-store` | 0.4.1 | `app/models/page.rb:97` | ✓ | ✓ | 1 | /store |
| `page-tag` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `page-tag-link` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `page-tags` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `page-type-recovery` | 0.4.1 (pattern) | `(dynamic)` |  |  | 1 | /recover-account |
| `page-type-signin` | 0.4.1 (pattern) | `(dynamic)` |  |  | 1 | /sign-in |
| `page-type-upgrade` | 0.4.1 (pattern) | `(dynamic)` |  |  | 1 | /upgrade |
| `pagination` | 0.4.1 | `app/helpers/search_helper.rb:18` | ✓ | ✓ | 2 | /collections |
| `pagination-info` | 0.4.1 | `app/views/collections/show.html.erb:33` | ✓ | ✓ | 2 | /collections |
| `pagination-next` | 0.4.1 | `app/views/collections/show.html.erb:38` |  |  | 2 | /collections |
| `pagination-prev` | 0.4.1 | `app/views/collections/show.html.erb:23` |  |  | 0 |  |
| `paid-content-gate` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3738` | ✓ | ✓ | 4 | /admin/themes/reference/forms |
| `paid-content-signin` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3768` | ✓ |  | 4 | /admin/themes/reference/forms |
| `paid-lock-icon` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2665` | ✓ | ✓ | 14 | /archive_2 |
| `player` | 0.4.1 | `app/helpers/posts_helper.rb:2` | ✓ | ✓ | 0 |  |
| `player-body` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2118` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-chapters` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2198` | ✓ | ✓ | 0 |  |
| `player-cover` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2105` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-duration` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2283` |  |  | 0 |  |
| `player-figure` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2107` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-link` | new | `app/models/content_layout/text.rb:131` |  |  | 0 |  |
| `player-main` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2120` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-native` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2091` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-next` | new | `app/models/concerns/has_markdown_extensions.rb:2129` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-now` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2090` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-now-episode` | new | `app/models/concerns/has_markdown_extensions.rb:2168` | ✓ | ✓ | 2 | /posts/01-my-comics-aren-t-for-kids |
| `player-now-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2123` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-now-title` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2090` |  |  | 16 | /admin/themes/reference/players |
| `player-paywall` | 0.4.1 | `app/site_js/player.js:602` | ✓ | ✓ | 0 |  |
| `player-playlist` | new | `app/models/concerns/has_markdown_extensions.rb:1971` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-playlist-count` | new | `app/models/concerns/has_markdown_extensions.rb:1971` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-playlist-podcast` | new | `app/models/concerns/has_markdown_extensions.rb:1969` |  |  | 10 | /podcast |
| `player-playlist-release` | new | `app/models/concerns/has_markdown_extensions.rb:1969` |  |  | 3 | /posts/maml |
| `player-prev` | new | `app/models/concerns/has_markdown_extensions.rb:2127` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-progress` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2131` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-progress-fill` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2132` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-progress-handle` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2133` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-series` | new | `app/models/concerns/has_markdown_extensions.rb:2266` | ✓ | ✓ | 11 | /posts/01-my-comics-aren-t-for-kids |
| `player-series-label` | new | `app/models/concerns/has_markdown_extensions.rb:2262` | ✓ | ✓ | 11 | /posts/01-my-comics-aren-t-for-kids |
| `player-series-next` | new | `(dynamic)` | ✓ | ✓ | 9 | /posts/01-my-comics-aren-t-for-kids |
| `player-series-prev` | new | `(dynamic)` |  |  | 9 | /posts/02-zombies-bad-chubby-good |
| `player-series-title` | new | `app/models/concerns/has_markdown_extensions.rb:2263` |  |  | 11 | /posts/01-my-comics-aren-t-for-kids |
| `player-speed` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2136` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-time` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2130` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-time-current` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2130` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-time-duration` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2135` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-toggle` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2128` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-track` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1944` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-track-audio` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1951` |  |  | 14 | /admin/themes/reference/players |
| `player-track-duration` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1939` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-track-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1948` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-track-meta` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1945` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-track-number` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1946` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-track-title` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1947` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-tracks` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1956` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `player-transport` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2126` | ✓ | ✓ | 16 | /admin/themes/reference/players |
| `player-video` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2062` | ✓ | ✓ | 5 | /admin/themes/reference/players |
| `playlist` | 0.4.1 | `app/models/collection_builder_schema.rb:78` | ✓ | ✓ | 14 | /admin/themes/reference/players |
| `podcast-episode` | 0.4.1 | `app/helpers/content_layout_helper.rb:14` |  |  | 9 | /posts/01-my-comics-aren-t-for-kids |
| `podcast-page-title` | 0.4.1 | `app/models/content_layout/explain.rb:214` |  |  | 1 | /podcast |
| `podcast-subscribe` | 0.4.1 | `app/models/content_layout/explain.rb:212` | ✓ | ✓ | 10 | /podcast |
| `podcast-subscribe--menu` | 0.4.1 | `app/views/content_layouts/parts/_subscribe.html.erb:57` | ✓ | ✓ | 0 |  |
| `poetry` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:364` | ✓ | ✓ | 1 | /admin/themes/reference/text |
| `post` | 0.4.1 | `app/helpers/content_layout_helper.rb:68` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-article` | 0.4.1 (pattern) | `(dynamic)` |  |  | 26 | /posts/aside-cards |
| `post-artist` | new | `lib/site_templates/minimum/documentation/roe/admin_layouts.md:174` |  |  | 2 | /posts/maml |
| `post-audio` | 0.4.1 (pattern) | `(dynamic)` |  |  | 2 | /posts/lab-audio |
| `post-author` | 0.4.1 | `app/models/content_layout/text.rb:85` | ✓ | ✓ | 29 | /posts/01-my-comics-aren-t-for-kids |
| `post-content` | 0.4.1 | `app/models/content_layout/explain.rb:228` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-date` | 0.4.1 | `app/models/content_layout/text.rb:76` |  |  | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-excerpt` | 0.4.1 | `app/models/content_layout/text.rb:67` | ✓ | ✓ | 0 |  |
| `post-field` | new | `app/models/content_layout/text.rb:172` |  |  | 0 |  |
| `post-header` | 0.4.1 | `app/helpers/content_layout_helper.rb:13` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-header-top` | 0.4.1 | `app/helpers/content_layout_helper.rb:13` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-image` | 0.4.1 | `app/views/content_layouts/parts/_image.html.erb:8` | ✓ | ✓ | 4 | /posts/collection-full |
| `post-link-large` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:5` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `post-link-medium` | 0.4.1 | `app/views/cards/_post_link_medium.html.erb:1` | ✓ | ✓ | 3 | /admin/themes/reference/cards |
| `post-link-small` | 0.4.1 | `app/views/cards/_post_link_small.html.erb:1` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `post-meta` | 0.4.1 | `app/helpers/content_layout_helper.rb:13` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-music` | 0.4.1 (pattern) | `(dynamic)` |  |  | 2 | /posts/maml |
| `post-player` | 0.4.1 | `app/models/content_layout/explain.rb:211` | ✓ | ✓ | 17 | /posts/01-my-comics-aren-t-for-kids |
| `post-podcast` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 9 | /posts/01-my-comics-aren-t-for-kids |
| `post-subtitle` | 0.4.1 | `app/models/content_layout/text.rb:57` | ✓ | ✓ | 17 | /posts/09-the-journal |
| `post-tag` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `post-tag-link` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `post-tags` | new | `app/models/content_layout/text.rb:68` | ✓ | ✓ | 0 |  |
| `post-title` | 0.4.1 | `app/services/substack_importer/converter.rb:501` | ✓ | ✓ | 43 | /posts/01-my-comics-aren-t-for-kids |
| `post-video` | 0.4.1? | `lib/site_templates/minimum/documentation/roe/tools_video_optimization.md:65` |  |  | 4 | /posts/closer-video |
| `private-feed` | 0.4.1 | `app/views/members/accounts/show.html.erb:204` | ✓ | ✓ | 0 |  |
| `private-feed-app` | 0.4.1 | `app/views/members/accounts/show.html.erb:223` |  |  | 0 |  |
| `private-feed-title` | 0.4.1 | `app/views/members/accounts/show.html.erb:206` | ✓ | ✓ | 0 |  |
| `private-feed-url` | 0.4.1 | `app/views/members/accounts/show.html.erb:207` | ✓ | ✓ | 0 |  |
| `private-feeds` | 0.4.1 | `app/views/members/accounts/show.html.erb:55` | ✓ | ✓ | 0 |  |
| `private-feeds-list` | 0.4.1 | `app/views/members/accounts/show.html.erb:202` | ✓ | ✓ | 0 |  |
| `private-feeds-note` | 0.4.1 | `app/views/members/accounts/show.html.erb:197` | ✓ | ✓ | 0 |  |
| `private-feeds-regenerate` | 0.4.1 | `app/views/members/accounts/show.html.erb:235` | ✓ | ✓ | 0 |  |
| `private-feeds-regenerate-form` | 0.4.1 | `app/views/members/accounts/show.html.erb:240` | ✓ | ✓ | 0 |  |
| `product` | 0.4.1 | `app/helpers/application_helper.rb:215` | ✓ | ✓ | 8 | /store/lab-poster |
| `product-button` | 0.4.1 | `app/views/shared/_snipcart_button.html.erb:14` |  |  | 0 |  |
| `product-button-error` | 0.4.1 | `app/services/product_button_renderer.rb:256` |  |  | 0 |  |
| `product-description` | new | `app/views/content_layouts/parts/_product_description.html.erb:6` |  |  | 0 |  |
| `product-excerpt` | new | `app/models/content_layout/explain.rb:220` | ✓ | ✓ | 0 |  |
| `product-grid` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4` | ✓ | ✓ | 4 | /admin/themes/reference/store |
| `product-image` | 0.4.1 | `app/helpers/products_helper.rb:7` | ✓ | ✓ | 8 | /store/lab-poster |
| `product-link-large` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:5` | ✓ | ✓ | 3 | /admin/themes/reference/store |
| `product-link-medium` | 0.4.1 | `app/views/cards/_post_link_medium.html.erb:1` | ✓ | ✓ | 2 | /admin/themes/reference/cards |
| `product-link-small` | 0.4.1 | `app/views/cards/_post_link_small.html.erb:1` | ✓ | ✓ | 2 | /admin/themes/reference/store |
| `product-notice` | 0.4.1 | `app/views/shared/_snipcart_button.html.erb:21` |  |  | 0 |  |
| `product-price` | 0.4.1 | `app/models/content_layout/explain.rb:223` | ✓ | ✓ | 6 | /admin/themes/reference/buttons |
| `product-subtitle` | new | `app/views/content_layouts/parts/_subtitle.html.erb:3` |  |  | 0 |  |
| `product-tag` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `product-tag-link` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `product-tags` | new | `app/models/content_layout/explain.rb:225` | ✓ | ✓ | 0 |  |
| `product-title` | 0.4.1 | `app/helpers/products_helper.rb:6` | ✓ | ✓ | 8 | /store/lab-poster |
| `product-top` | 0.4.1 | `app/helpers/content_layout_helper.rb:14` | ✓ | ✓ | 8 | /store/lab-poster |
| `product-variant` | 0.4.1 | `app/views/cards/_post_link_large.html.erb:9` | ✓ | ✓ | 2 | /admin/themes/reference/store |
| `product-variant-item` | 0.4.1 | `app/services/product_button_renderer.rb:57` | ✓ | ✓ | 6 | /admin/themes/reference/buttons |
| `product-variant-list` | 0.4.1 | `app/services/product_button_renderer.rb:64` | ✓ | ✓ | 6 | /admin/themes/reference/buttons |
| `pullquote-center` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 4 | /admin/themes/reference/cards |
| `pullquote-left` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3002` | ✓ | ✓ | 3 | /admin/themes/reference/cards |
| `pullquote-merge` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3012` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `pullquote-right` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3002` | ✓ | ✓ | 5 | /admin/themes/reference/cards |
| `recovery-link-block` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3995` |  |  | 0 |  |
| `release-page-title` | new | `app/models/content_layout/explain.rb:215` |  |  | 1 | /yitta-bitta-soft-sphinx-energy |
| `release-subscribe` | new | `app/views/content_layouts/parts/_subscribe.html.erb:80` |  |  | 0 |  |
| `screenshot` | 0.4.1 | `lib/site_templates/minimum/documentation/roe/DAB-content_media.md:32` | ✓ | ✓ | 0 |  |
| `share` | 0.4.1 | `app/models/action_builder_schema.rb:20` | ✓ | ✓ | 5 | /admin/themes/reference/buttons |
| `share-center` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4251` | ✓ | ✓ | 0 |  |
| `share-left` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `share-right` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `share-small` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:4251` | ✓ | ✓ | 0 |  |
| `sidebar-left` | 0.4.1 (pattern) | `(dynamic)` |  |  | 118 | / |
| `sidebar-mobile-bottom` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `sidebar-mobile-style-horizontal` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `sidebar-mobile-style-vertical` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `sidebar-mobile-top` | 0.4.1 | `(dynamic)` | ✓ | ✓ | 48 | / |
| `sidebar-right` | 0.4.1 | `(not found — dead)` | ✓ | ✓ | 0 |  |
| `signin-link-block` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3942` |  |  | 0 |  |
| `signin-recovery-link` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3968` |  |  | 3 | /admin/themes/reference/forms |
| `signup-closed` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3846` |  |  | 0 |  |
| `signup-link-block` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:3831` |  |  | 0 |  |
| `site-action` | 0.4.1 | `app/views/layouts/site.html.erb:195` | ✓ | ✓ | 118 | / |
| `site-actions` | 0.4.1 | `app/views/layouts/site.html.erb:170` | ✓ | ✓ | 118 | / |
| `site-footer` | 0.4.1 | `app/views/layouts/site.html.erb:132` | ✓ | ✓ | 118 | / |
| `site-logo` | 0.4.1 | `lib/site_templates/minimum/documentation/roe/admin_layouts.md:80` | ✓ | ✓ | 118 | / |
| `site-nav` | 0.4.1 | `app/views/layouts/site.html.erb:96` | ✓ | ✓ | 118 | / |
| `site-search` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1026` | ✓ | ✓ | 118 | / |
| `site-search--open` | 0.4.1 | `app/site_js/search.js` |  |  | 0 |  |
| `site-search-box` | 0.4.1 | `app/views/shared/_site_search.html.erb:22` | ✓ | ✓ | 118 | / |
| `site-search-close` | 0.4.1 | `app/site_js/search.js:58` | ✓ | ✓ | 118 | / |
| `site-search-context` | 0.4.1 | `app/views/shared/_site_search.html.erb:24` | ✓ | ✓ | 118 | / |
| `site-search-context-label` | 0.4.1 | `app/site_js/search.js:318` | ✓ | ✓ | 0 |  |
| `site-search-context-remove` | 0.4.1 | `app/site_js/search.js:324` | ✓ | ✓ | 0 |  |
| `site-search-empty` | 0.4.1 | `app/views/shared/_site_search.html.erb:34` | ✓ | ✓ | 118 | / |
| `site-search-field` | 0.4.1 | `app/views/shared/_site_search.html.erb:25` | ✓ | ✓ | 118 | / |
| `site-search-input` | 0.4.1 | `app/views/shared/_site_search.html.erb:26` | ✓ | ✓ | 118 | / |
| `site-search-overlay` | 0.4.1 | `app/views/shared/_site_search.html.erb:21` | ✓ | ✓ | 118 | / |
| `site-search-result` | 0.4.1 | `app/site_js/search.js:344` | ✓ | ✓ | 0 |  |
| `site-search-result-excerpt` | 0.4.1 | `app/site_js/search.js:379` | ✓ | ✓ | 0 |  |
| `site-search-result-head` | 0.4.1 | `app/site_js/search.js:366` | ✓ |  | 0 |  |
| `site-search-result-link` | 0.4.1 | `app/site_js/search.js:155` | ✓ | ✓ | 0 |  |
| `site-search-result-link--active` | 0.4.1 | `app/site_js/search.js:164` | ✓ | ✓ | 0 |  |
| `site-search-result-paid` | 0.4.1 | `app/site_js/search.js:371` | ✓ | ✓ | 0 |  |
| `site-search-result-type` | 0.4.1 | `app/site_js/search.js:354` | ✓ | ✓ | 0 |  |
| `site-search-result-type-add` | 0.4.1 | `app/site_js/search.js:357` | ✓ |  | 0 |  |
| `site-search-results` | 0.4.1 | `app/views/shared/_site_search.html.erb:33` | ✓ | ✓ | 118 | / |
| `site-search-toggle` | 0.4.1 | `app/site_js/search.js:57` | ✓ | ✓ | 118 | / |
| `site-search-trigger` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:1029` | ✓ | ✓ | 4 | / |
| `site-sidebar` | 0.4.1 | `app/views/layouts/site.html.erb:127` | ✓ | ✓ | 48 | / |
| `snipcart-add-item` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2490` |  |  | 2 | /admin/themes/reference/buttons |
| `snipcart-cart--opened` | 0.4.1 | `app/views/layouts/site.html.erb:392` | ✓ | ✓ | 0 |  |
| `snipcart-checkout` | 0.4.1 | `app/views/layouts/site.html.erb:195` |  |  | 0 |  |
| `snipcart-items-count` | 0.4.1 | `app/views/layouts/site.html.erb:197` | ✓ | ✓ | 0 |  |
| `snipcart-link` | 0.4.1 | `app/views/layouts/site.html.erb:178` | ✓ | ✓ | 0 |  |
| `snipcart-sidecart--opened` | 0.4.1 | `app/views/layouts/site.html.erb:392` | ✓ | ✓ | 0 |  |
| `subscribe-links` | 0.4.1 | `app/views/content_layouts/parts/_subscribe.html.erb:29` | ✓ | ✓ | 10 | /podcast |
| `title-media-icon` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:2678` | ✓ |  | 10 | /admin/themes/reference/collections |
| `upgrade-link` | 0.4.1 | `app/views/members/accounts/show.html.erb:184` |  |  | 0 |  |
| `variant-current` | 0.4.1 | `app/services/product_button_renderer.rb:209` | ✓ | ✓ | 4 | /store/lab-tee |
| `variant-name` | 0.4.1 | `app/services/product_button_renderer.rb:58` | ✓ | ✓ | 6 | /admin/themes/reference/buttons |
| `variant-price` | 0.4.1 | `app/services/product_button_renderer.rb:156` | ✓ | ✓ | 6 | /admin/themes/reference/buttons |
| `video-btn` | 0.4.1 | `app/views/shared/_video_player.html.erb:52` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-controls` | 0.4.1 | `app/views/shared/_video_player.html.erb:42` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-controls-bar` | 0.4.1 | `app/views/shared/_video_player.html.erb:50` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-controls-left` | 0.4.1 | `app/views/shared/_video_player.html.erb:51` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-controls-right` | 0.4.1 | `app/views/shared/_video_player.html.erb:60` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-embed` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:185` | ✓ | ✓ | 2 | /admin/themes/reference/media |
| `video-external` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:127` |  |  | 1 | /posts/the-long-post |
| `video-external-link` | 0.4.1 | `app/services/video_embed.rb:159` |  |  | 0 |  |
| `video-external-youtube` | 0.4.1 (pattern) | `(dynamic)` |  |  | 1 | /posts/the-long-post |
| `video-player-container` | 0.4.1 | `app/models/concerns/has_markdown_extensions.rb:127` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-player-video` | 0.4.1 | `app/services/video_renderer.rb:38` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-progress` | 0.4.1 | `app/views/shared/_video_player.html.erb:43` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-progress-fill` | 0.4.1 | `app/views/shared/_video_player.html.erb:46` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-progress-handle` | 0.4.1 | `app/views/shared/_video_player.html.erb:47` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-time` | 0.4.1 | `app/views/shared/_video_player.html.erb:61` | ✓ | ✓ | 6 | /admin/themes/reference/media |
| `video-time-separator` | 0.4.1 | `app/views/shared/_video_player.html.erb:63` | ✓ |  | 6 | /admin/themes/reference/media |
| `w-5` | 0.4.1 | `app/helpers/application_helper.rb:272` |  |  | 83 | /about |
| `warning` | 0.4.1 | `app/views/shared/_snipcart_button.html.erb:21` |  |  | 0 |  |
| `page-<url_name>` | 0.4.1 (pattern) | `app/views/pages/show.html.erb:9` | `page-store`, `page-documentation` | same | every page | / |
| `language-<lang>` | 0.4.1 (pattern) | `app/models/concerns/has_markdown_extensions.rb` | | | docs | /documentation/roe/themes |

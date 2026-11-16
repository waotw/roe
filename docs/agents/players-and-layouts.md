# Players, playlists and content layouts

Status: **shipped in 0.4.x–0.5.0.** Checked against the code on 2026-11-13.

The decisions behind how a post or page plays its audio and video, and how a
content layout arranges a page. Most of these were settled after something
else was built and taken out; the reasons are here so it isn't built again.

---

## Direction

Every player lives in Markdown: a ```` ```card ```` with `type: player` for
one item, and a `template: playlist` collection for a list. The post-type ERB
templates are a transition layer for older posts. New player features go into
the card or the playlist, never into the ERB templates. The card's look —
monospace, `.card-player`, ♪ title, ▶, a bar, the times — is the base; build
on its CSS rather than adding another style.

---

## A player plays, a playlist lists

- They are **always separate, paired by position.** `player.js` gives each
  playlist to the nearest player above it (player.js 1.5; before that, each
  player took the first untaken playlist after it, so a player higher up the
  page stole the list meant for the one beside it). A player with no playlist
  anywhere below it takes the first on the page. A page can hold several
  pairs. A list drawn inside the card, and a playlist
  with its own player, were both built and removed.
- A playlist with no player is **links**: each row goes to its post with
  `?play`, which starts playing on arrival (a real click is needed; a direct
  navigation has no user gesture and the browser blocks it, correctly).
- `ContentLayout` warns on `[playlist]` without `[player]`. It's a warning,
  never a stand-in player.
- **The fold belongs to the playlist** (`render_playlist`, `fold:`): folded
  on a music or podcast post, which is about its own track or episode; open
  everywhere else. The summary names the release or podcast when every row
  shares one ("Episodes 9 - <podcast>"); the " - " is text, not CSS, so
  themes that don't style the name still read.
- A row with no `episode_number` / `track_number` shows a blank number, never
  its position. The blank is the cue to add one.
- **One player per file** (`Post#show_template_player?`): the template draws
  a player only when the body has no player card for the post's own media. A
  card playing another file (a song in a podcast's show notes) is extra; the
  post's player stays.

## Touch

- Option C of three Figma mocks: `@media (pointer: coarse)`, not a width
  breakpoint (an iPad is wide but finger-only). Artwork hidden, a full-width
  bar between the times, ⏮ ▶ ⏭ 1× as large cells along the bottom.
- ⏮ ⏭ ship `hidden disabled`. `player.js` (1.4) shows them only when the
  theme sets `--player-nav: 1` on `.card-player`, so new JS on an old theme
  never shows two empty buttons.
- Both shipped themes keep the player in `var(--font-mono)`, bare included
  (chosen after a serif mock). Don't repoint `--font-mono` to
  change a player's font: it also styles code blocks.

## Old themes and new markup

Theme and `player.js` updates are offered in Admin → Updates, never applied
automatically, so new markup reaches sites with older CSS and JS.

- The play button is empty; the theme draws ▶ with `.player-toggle::before`.
  On a theme with no player styles, `PlayerThemeCheck.styled?` makes the card
  plain `<audio controls>` with no `data-player`, which any `player.js`
  leaves alone. Never put a glyph in the button text: every existing theme's
  `::before` would double it.
- Every player rule in a theme is scoped to `.card-player` (the playlist's to
  `.collection.playlist`). An unscoped rule left from the old player drew a
  grey band on desktop only.

---

## Content layouts

A layout is plain text — rows of `[boxes]` in blocks — that says what a
content type's page shows around its writing (`ContentLayout`, header
comment). The site's copy is `site/layout/content/<type>.txt`; Roe's defaults
are `lib/site_templates/layouts/content/`. Off until enabled in Settings →
Content (`content_layouts`); off, the defaults are used and saved layouts are
kept.

- **A box behaves exactly like its Markdown block**: `[player]` is the player
  card, `[playlist]` the playlist collection — same markup, defaults and
  fallback. A box with a special case its block lacks was built and reverted.
- **The body wins** (`ContentLayout::BodyCheck`): a player card, playlist or
  buy button in the writing replaces the layout's.
- **Audio and video come before the text**, on posts too: the music, podcast,
  audio and video defaults put `[player]` (and `[playlist]`) above `[body]`.
  Email and feeds turn the player into a Listen link, so this is safe.
- Pages have no media of their own: on a page with `release:` / `podcast:`,
  `[player]` is an empty card that plays the playlist after it.
- Boxes on one line share a `<div>` (the row's name, or `.layout-row`) for CSS
  to style; **Roe doesn't lay them out**. The shipped themes leave
  `.layout-row` unstyled on purpose, so boxes on one line stack; a theme can
  lay the row out. Side by side was tried and looked worse. A
  `[player] [playlist]` row keeps the joined border, since the two are still
  neighbours inside the row.
- **`.content` wraps the whole layout** on every type (posts, pages, docs,
  products), so Markdown styles reach the boxes too. The writing alone is
  `.post-content`, `.page-content` or `.documentation-content`; a product's
  writing has no wrapper, because the product grid styles `.content`'s direct
  children. Docs are `article.documentation-page > .content.documentation`, so
  `article .content` (the aside column) and `.content.documentation` rules
  both match. Putting `.content` on `[body]` only was measured and rejected:
  the product page falls apart, and every site theme written against
  `article .content` would change without an update to accept.
- A site's saved layout overrides Roe's default, so a copy of an older
  default hides a box the new one gained. When diagnosing "no player", check
  the site's layout file first.

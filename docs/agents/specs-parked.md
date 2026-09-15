# Parked designs

Two designs that were agreed in detail and deliberately not built. They are
recorded here so the thinking is not lost and so nobody redesigns them from
scratch.

---

# 1. Media usage index — durable rearchitecture

**Status: parked. Do after 0.1.0.**

This is a scale problem, not a problem most users have. The current scan is fine
for small sites. It starts to matter at **hundreds of images** — for both speed
and accuracy — and on **synced or hosted instances**, where a user hit a bug that
reported used images as unused.

## What's wrong with today's design

`MediaUsageIndex` is a monolithic scan-cache:

- It builds the whole map at once by regex-scanning every Post, Page, Documentation,
  and Product body plus the config.
- It is discarded on every content, media, or config save, so full rebuilds are
  frequent, and the cost scales with *total content* rather than with the number
  of media files.
- Below 200 images there is no cache at all, so every browse load triggers a full
  scan.
- It is **blind to ContentSync and Site Sync.** Bulk writes bypass the
  `after_commit` hooks, so the index goes stale and reports files as unused. This
  is the reported bug.
- Browse loads *all* media, with no pagination, because the tab and unused filters
  run client-side.
- Two overlapping systems exist: the `media_references` join table (posts only)
  and the `MediaUsageIndex` scan-cache.

## The target: a durable reverse index

Generalise the existing `media_references` table into the single source of truth,
maintained incrementally.

- One row per (media file, referencing source). The source is generic: content
  records (Post, Page, Documentation, Product) **and** non-record sources such as
  config files and the active theme CSS.
- "Unused" becomes **live SQL** — a media original with zero reference rows.
  Always accurate, instant, no scan.
- "Used in" becomes a join. Instant.

### Maintenance, which is the crux

- **Content record saved** → rescan just that record for `/media/` paths and
  reconcile its rows, adding new and dropping gone. Cost is one record.
- **Content record destroyed** → rows cascade away.
- **Media uploaded** → no reference change; a new file starts with zero references,
  which correctly reads as unused. Deleting removes the file and its rows.
- **Config or theme saved** → rebuild that source's rows. Few files, cheap.
- **ContentSync `sync_all`** → references re-sync as records are written, and the
  run ends with a full rebuild pass as a safety net. **This is the self-repair.**
  References re-derive from ordinary usage, so there is no separate cache anyone
  has to remember to invalidate, and the Site Sync hole closes structurally.
- There is no monolithic cache to invalidate. The table *is* the index.

### Sources

Keep: Post, Page, Documentation, and Product content and metadata; `site.yml` and
`podcast.yml` for logo and artwork, which are already scanned.

Add: the active theme CSS. The media regex only matches `/media/…`, so this is
one cheap pass — a long file is not a real cost here.

Skip: `collections.yml`, `cards.yml`, `store.yml`, `snipcart.yml`. Confirmed to
contain no media paths.

## The browse performance win

Making "unused" and type into SQL filters unlocks server-side filtering and
**pagination** — loading a page of media at a time instead of hundreds of cards at
once, which is the real bottleneck. Thumbnails are already lazy-loaded with small
variants. Tab counts become cheap `COUNT` queries.

## Accuracy and safety

Tests should cover: references correct after save, destroy, and sync; a synced
post's images never reported unused; the unused set equals exactly the zero-reference
set; a rename keeps references correct.

Self-repair comes from the ContentSync rebuild pass plus a re-runnable rake task,
extending the existing `media_reference:rebuild`.

No delete-time stopgap is needed, since the index is structurally correct. Keep a
bulk-delete confirmation modal past roughly 15 files as plain interface safety,
mirroring posts.

## Retire

The scan-cache `MediaUsageIndex`, or reduce it to a thin query facade. Fold the
posts-only `MediaReference` semantics into the generalised table, so there is one
system rather than two.

## Rollout

A migration to generalise the table plus a one-time idempotent backfill that scans
everything once. Ship the maintenance callbacks and the ContentSync rebuild
together with the backfill, so the table is populated and stays current. Then
repoint browse at the table and add pagination.

## Decisions left for build time

- The generic-source shape: a polymorphic `referenceable` versus `source_kind`
  plus `source_key`. Config and theme have no ActiveRecord record, so the leaning
  is `source_kind` plus `source_key`.
- Whether to keep a thin `MediaUsageIndex` facade or replace the call sites.
- Pagination style: pages or infinite scroll, and how the tab filter and search
  compose with it.
- Theme CSS: active theme only, or all theme files.

## If the bug recurs before the refactor

An optional stopgap: invalidate `MediaUsageIndex` at the end of ContentSync and in
the Site Sync apply path. That plugs the specific hole without the rearchitecture.
Ben declined the broader invalidation-patching approach in favour of fixing it
structurally, so treat this as a fallback only.

---

# 2. Importer pipeline decomposition

**Status: designed and agreed, not built.**

Break the working end-to-end Substack importer into composable, reusable parts,
instead of building a bespoke importer for every source.

The pipeline: **source adapter → normalised SourceDoc → field mapper → post
writer → (separate) media importer.**

Members and deliveries stay a separate track, since they touch the database,
Stripe, and audience. Substack only for now; other formats later.

## SourceDoc, the contract every adapter emits

- `source_id` — the idempotency key
- `kind` — `:post` or `:page`
- `body` plus `body_format` (`:html` or `:markdown`) — this is where HTML becomes
  Markdown
- `frontmatter` — arbitrary source keys, kept verbatim
- `origin` — path, mtime, or URL, for fallbacks

Planned adapters: Substack ZIP, RSS feed, Obsidian or Markdown directory, HTML
crawl.

## Field mapper

Declarative per-source profiles with resolver chains — for example
`date` resolves from `date`, then `published_date`, then `pubDate`, then `created`,
then the file mtime.

Unknown source keys pass through verbatim, since Roe tolerates extra frontmatter
by folding it into `metadata`. That means custom Obsidian fields survive the trip.

Ship code-defined profiles first, **not** a visual mapping interface.

## Media importer

A decoupled pass that runs afterwards. Posts import instantly while still
referencing remote `http(s)://` URLs, and they work in Roe that way. Localising
media — download, place in the right `/media/<type>/` folder, rewrite the
reference, upsert the `Medium` — is a separate, resumable, opt-in pass over all or
selected posts.

This generalises the "localise podcast audio later" request. It needs its own
durable tracking of posts with outstanding external media, which is what finally
justifies the media usage index rearchitecture above.

## The podcast episode importer

It decomposes into an RSS source adapter plus the generic media importer. Nothing
from that scope is lost.

## Build order, as agreed

1. Generic importer, RSS adapter, and Markdown-directory adapter — importing as
   drafts, with remote media and no downloading.
2. The standalone media importer, plus a fix to `FeedGenerator` for remote
   enclosures.
3. Migrate Substack onto the pipeline as an adapter. This is what enables
   open-sourcing it.
4. Generalise members and deliveries.

## Constraints

- **Do not refactor the working Substack importer first.** The regression risk is
  too high. Build the new pipeline for new sources and migrate Substack last, once
  the pipeline has earned trust.
- The generic HTML-to-Markdown converter must separate generic conversion from
  Substack-specific cleanup filters — paywalls, subscribe widgets, CDN URLs — made
  opt-in per profile.
- Idempotency stays uniform across adapters via
  `json_extract(metadata,'$.<source_id_field>')` skip checks.
- Import as drafts. Skip by guid.

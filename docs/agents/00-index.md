# Agent notes

Working memory for anyone — person or agent — picking up work on Roe.

Decisions, conventions, and hard-won detail that a newcomer to the codebase — or
an agent — would otherwise have to rediscover. The conventions are summarised in
[`AGENTS.md`](../../AGENTS.md); the reasoning behind them lives here.

| File | What's in it |
|---|---|
| [conventions.md](conventions.md) | What not to do without asking, and why. **Read this first.** |
| [authoring-map.md](authoring-map.md) | Which copy of a file is the source of truth, plus traps that have each cost an afternoon. |
| [backups-secrets-and-data.md](backups-secrets-and-data.md) | Backup and restore architecture, encryption keys, where secrets live, member data. |
| [site-sync.md](site-sync.md) | Site Sync since 0.5.0: the version store, Sync History, REWIND, conflicts, the deletion guard, and what backups are for now. |
| [players-and-layouts.md](players-and-layouts.md) | How players, playlists and content layouts behave, and why. |
| [theme-reference.md](theme-reference.md) | The admin theme reference pages: where they live, the rolled-back sample content, features shown as on. |
| [theme-editor.md](theme-editor.md) | The theme editor: CodeMirror 6, the in-page preview, SECTIONS, INSPECT, SAVE AS…. |
| [site-classes.md](site-classes.md) | Every public site CSS class, which shipped, the 0.5.0 changes, and the naming exceptions kept on purpose. |
| [roadmap.md](roadmap.md) | Status and direction for the larger pieces of work. |
| [specs-parked.md](specs-parked.md) | Designs agreed but deliberately not built, including Sync History per-file restore. |

## How to use these

- `conventions.md` is binding. Each item is a standing instruction.
- Everything else is context. When a note and the code disagree, the code wins —
  then fix the note.
- When a decision gets made that someone later would need and could not infer
  from the code, add it here.

These notes sit under `current/docs/` rather than in `site/` or a dotfile
directory on purpose: most agent search tools skip ignored and hidden paths, so
notes kept there would never be found. Note that `docs/` is excluded from the
normal installer zip — it ships only with `bin/build-installer --with-dev-docs`.

## Staleness

Roe moves quickly, so a note describing a plan may be describing something that
has already shipped. The following were checked against the code on 2026-09-15
while converting these notes:

- **Ruby 4.0.5 has shipped.** `current/.ruby-version` is `4.0.5` and the Gemfile
  declares `csv` and `ostruct`.
- **Site Sync over HTTP has shipped.** `current/app/services/site_sync/` holds the
  full implementation, including the conflict reconciler.
- **The `backups/` layout has shipped** and replaced `site_backups/`.
- **The primary repository is now GitHub**, with Codeberg and Sourcehut as push
  mirrors. Older notes referring to Codeberg as primary predate that move.
- **Snipcart stores no provider secret key.** Its store runs on a public
  snippet, so `SnipcartConfig` has no encrypted Snipcart API key. Its webhooks
  are authenticated by an unguessable path token (a `webhook_token` column, not
  an `encrypts` attribute) — a deliberate choice over Snipcart's secret-key
  validation; see [backups-secrets-and-data.md](backups-secrets-and-data.md).

Checked again on 2026-11-13 for 0.5.0:

- **Site Sync keeps every version a sync replaces** (`backups/versions/`), and
  syncs no longer take a local snapshot. See [site-sync.md](site-sync.md).
- **Resolving conflicts finishes the sync** in the same run; the roadmap's old
  "run the sync again afterwards" follow-up is done.
- **Ruby is 4.0.10** (`current/.ruby-version`), a security update from 4.0.5.
  How a Ruby change reaches each install: [roadmap.md](roadmap.md#changing-the-ruby-version-how-each-install-gets-it).

Nothing in `conventions.md` has expired. Those still stand.

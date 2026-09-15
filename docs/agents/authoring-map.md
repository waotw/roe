# Authoring map and known traps

Several files in Roe exist in two places: one you edit, one that ships. Editing
the wrong copy is wasted work — it gets overwritten on the next sync. This file
records which copy wins, plus the traps that have each cost an afternoon.

## Which copy is the source of truth

| Thing | Edit this | Never edit this | Why |
|---|---|---|---|
| Theme CSS | `site/theme/*.css` | `current/app/themes/*.css` | `site/theme/` is hand-edited, then rsynced into `app/themes/` by `bin/sync-from-site`. The shipped copy is downstream. |
| Roe documentation | `site/documentation/roe/*.md` | `current/lib/site_templates/minimum/documentation/roe/*.md` | Same pattern: authored in `site/`, rsynced to the shipped copy. |
| Doc version stamps | nothing | `site/documentation/roe/_versions.yml` | System-generated on version bump. Hand edits get overwritten. |
| `roe.sh`, `README.md`, `LICENSE` | the copies in `current/` | the copies at the project root | `bin/sync-from-site` mirrors these up to the root, and the in-app updater does the same on user installs (`UpdateOrchestrator::ROOT_SYNC_FILES`). Edit the root copy and you lose it on the next sync. |

If you run a second install alongside this one, move code between them with git —
commit and push in one, pull in the other — rather than copying files across.
Second installs also tend to leave traces here: `app/themes/egg.css` is one such
theme and is gitignored on purpose.

### Theme CSS

The CSS actually served comes from `site/theme/`, not from `current/app/themes/`.
The active theme is set by `theme.active` in `site/system/global/site.yml`.

Roe ships `bare.css` and `default.css`, and an install may hold personal variants
alongside them. **Always check `theme.active` in `site.yml` before editing**, then
read that file for the rules actually in effect — don't assume a default.

CSS edits belong in the active theme, plus `default.css` when the change belongs
in the shipped standard theme. Editing `app/themes/` as well is redundant and
will be overwritten.

See [conventions.md](conventions.md) for the rule about which section of the file
a new rule goes in.

### Documentation

Edit only `site/documentation/`. If the two trees diverge, `site/` wins.
Documentation work is a standing exception to the "ask before touching `site/`"
rule, but only when doc work has actually been requested.

One removal worth remembering: `site/documentation/roe/markdown-extensions.md`
was deleted as a stale duplicate of `roeanji.md`. Do not recreate it. The live
reference is `roeanji.md` plus the per-topic `roeanji_*.md` deep dives.

---

## Known traps

### A new Stimulus controller doesn't load

**Symptom:** A newly added controller works in propshaft resolution but does not
appear in `bin/importmap json`, so `eagerLoadControllersFrom` never registers it
and its `data-controller` does nothing.

**Cause:** A leftover `public/assets/.manifest.json` from a local
`assets:precompile` (usually deploy testing) puts propshaft into precompiled mode,
which shadows dev's on-the-fly asset resolution. Any controller added after that
precompile is invisible to the importmap. This is **not** a `pin_all_from` bug —
it has been misdiagnosed as one twice.

**Fix:** `bin/rails assets:clobber`.

`public/assets` is gitignored, so a stale manifest is always a local artifact. It
cannot arrive through git, and production is unaffected because the deploy
precompiles fresh.

Registration itself is standard: `pin_all_from "app/javascript/controllers"` in
`importmap.rb` plus `eagerLoadControllersFrom("controllers", application)` in
`controllers/index.js`.

### The in-app updater refuses to run on a dev checkout

This is deliberate. The updater clones a release tag **over `current/`**, which
destroys the working tree and any uncommitted work.

This actually happened: an old "Test nightly" button passed `prerelease=true` to
slip past the guard, and an entire uncommitted feature — encrypted database
backups — was wiped. It was rebuilt from the session transcript and committed.

The guard now has two layers:

- `Admin::UpdatesController#block_on_dev_install` — the prerelease bypass is
  gone. A dev checkout is blocked on `start` and `rollback`, no exceptions.
- `RoeUpdater::UpdateOrchestrator.start_update` — `refuse_on_dev_checkout!` runs
  before any destructive step, so every entry point is covered, including rake
  and a direct `PerformUpdateJob` enqueue.

`dev_install?` is true when `git symbolic-ref --quiet HEAD` succeeds, meaning
HEAD is on a named branch. A user install is a detached release tag, so users are
not blocked.

**Escape hatch:** `ROE_ALLOW_DEV_UPDATE=1`. Only for exercising the updater on a
throwaway install — never the main dev checkout. To test the updater properly,
use a separate detached-tag install.

**The lesson from the loss:** push work-in-progress branches frequently. The work
that was destroyed was uncommitted and local only, so nothing off the machine had
it.

### Release tags need the `v` prefix

`RoeUpdater::VersionChecker` ignores bare-numbered tags. Tags must look like
`v0.1.0`. Suffixed tags (`-nightly.N`, `-rc.N`) are treated as pre-releases and
shown only to dev installs or the `nightly` channel.

The primary repository is GitHub, with Codeberg and Sourcehut as push mirrors.
`RoeUpdater::Forge` holds the mirror list the updater reads, first answer wins —
so a tag pushed to only one mirror is invisible to the others. One
`git push roe main --tags` fans out to all three.

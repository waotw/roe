# Authoring map and known traps

Several files in Roe exist in two places: one you edit, one that ships. Editing
the wrong copy is wasted work — it gets overwritten on the next sync. This file
records which copy wins, plus the traps that have each cost an afternoon.

## Which copy is the source of truth

| Thing | Edit this | Never edit this | Why |
|---|---|---|---|
| Theme CSS | `site/theme/*.css` | `current/app/themes/*.css` | Ben hand-edits `site/theme/`, then rsyncs it into `app/themes/`. The shipped copy is downstream. |
| Roe documentation | `site/documentation/roe/*.md` | `current/lib/site_templates/minimum/documentation/roe/*.md` | Same pattern: authored in `site/`, rsynced to the shipped copy. |
| Doc version stamps | nothing | `site/documentation/roe/_versions.yml` | System-generated on version bump. Hand edits get overwritten. |
| Code for the `/egg` install | `/roe` then commit and push | `/egg/current/**` | See below. |

### Theme CSS

The CSS actually served comes from `site/theme/`, not from `current/app/themes/`.
The active theme is set by `theme.active` in `site/system/global/site.yml`.

**In this install the active theme is `bare`**, so the live file is
`site/theme/bare.css`. Also present: `default.css` (the shipped standard theme)
and `default-ben.css` (a personal variant). Check `site.yml` to confirm which is
live, then read that file for the rules actually in effect.

CSS edits belong in the active `bare.css`, plus `default.css` when the change
belongs in the shipped standard theme. Ben has confirmed twice that editing
`app/themes/` as well is redundant and will be overwritten.

See [working-agreements.md](working-agreements.md) for the rule about which
section of the file a new rule goes in.

### Documentation

Edit only `site/documentation/`. If the two trees diverge, `site/` wins. Ben has
standing permission-in-advance for documentation edits under
`site/documentation/` when he has asked for doc work.

One removal worth remembering: `site/documentation/roe/markdown-extensions.md`
was deleted as a stale duplicate of `roeanji.md`. Do not recreate it. The live
reference is `roeanji.md` plus the per-topic `roeanji_*.md` deep dives.

### The `/egg` install

Ben maintains two sibling installs: `/Volumes/S&M 2019/Code/roe` (primary) and
`/Volumes/S&M 2019/Code/egg` (an author and test site on Fly). Code moves from
roe to egg by committing and pushing in roe, then pulling in egg.

So do not propose copying individual files into egg, and do not edit anything
under `/egg/current/`. Draft a commit message (without running the commit — rule
1) and the change will flow through the normal push and pull.

Note that `app/themes/egg.css` belongs to that other site and is gitignored here.

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

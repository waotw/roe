# Site Sync: history, rewind, conflicts and deletions

Status: **shipped in 0.5.0.** Checked against the code on 2026-11-13.

How a sync decides what to move (the ledger, the three-way reconcile, the
baseline rules) is in [roadmap.md](roadmap.md#site-sync-over-http--shipped).
This note covers what came after: keeping every version a sync replaces,
Sync History and REWIND, opening files before a sync, the conflict screen,
the deletion guard, and why backups changed. Each section says what was
decided and why, because most of it was argued over and some of it was built
and then removed.

---

## The model people should have

Site Sync should feel like **one site in two places** unless something goes
wrong. Roe doesn't yet know how people use it — live only, local then push,
or as a backup — so the history tools are for recovering from a mistake, not
for managing versions day to day. When a design adds states someone has to
keep in their head (restored here but not yet there, partly rewound), it was
dropped. Keep that test for anything new.

---

## The version store (`SiteSync::Versions`)

Every version a sync replaces or deletes, on either side, is saved before the
sync touches it.

- `backups/versions/history.sqlite3` holds one row per changed path per
  event (`before_sha`, `after_sha`, sizes, modified times, direction, action);
  `backups/versions/objects/ab/cdef…` holds the contents, named by SHA-256, so
  identical contents are stored once.
- Opened with the `sqlite3` gem directly, not as a Rails database: no
  migrations, created on first use, and the updater's database rollback
  can't touch it. Schema changes go through `user_version` and must be
  additive (v2 added columns in place; an older Roe still reads the file).
  Opening the page upgrades the file, so treat a schema change like a
  migration: test against a copy, and say that it happens on first view.
- It lives in `backups/`, outside `site/`, so it never syncs. Live keeps
  nothing: live's old copies are downloaded before a push and kept here.
- Kept 30 days by default (`sync_history_days`; `0` or `forever` keeps
  everything). Trimming removes old events, then contents nothing points to.

**Rules, all load-bearing:**

1. Contents are saved first, then the row, in one step. A crash leaves an
   unused copy, never a row pointing at nothing.
2. **No saved copy, no deletion or overwrite.** `Recorder#save_local!` and
   `#save_live!` raise `Versions::SaveFailed` and the sync stops before
   transferring. A live file in the peer manifest but missing from the
   pre-push backup stops the push (except video web versions, which are left
   out of backups on purpose and remade). Don't soften this into a warning:
   the relaxed deletion guard below is only safe because of it.
3. The store records what a sync did. It never decides what a sync does; if
   it's missing or empty, syncing behaves as before.

**What gets copied:**

- The version a sync **replaces** is always copied, at any size.
- The version a sync **leaves** is copied only when it's 10 MB or under
  (`AFTER_COPY_MAX`); a larger one is fingerprinted. Without the copy, a
  later local edit makes FILE/DIFF of that sync impossible, because the
  version no longer exists anywhere.
- **Live's old copies are hard-linked in, not copied** (`Versions.link_file`,
  falling back to a copy across disks). They arrive in the pre-push backup
  `backups/live/content/<time>/`, which `save_live!` then removes, moving
  `latest` to the newest folder left. One copy on disk.
- **Never hard-link a file in `site/`.** An edit to the file would change
  the stored version with it. Only files nothing writes to again (the
  pre-push backup) may be linked.

**Only syncs are recorded.** Saves in the admin (CSS editor, settings, posts)
are not versioned. That was stage 5 of the original plan, decided against for
now (2026-11-13). Nothing built depends on it.

---

## Sync History

`/admin/site_sync/history` lists each sync: what went LOCAL TO LIVE and LIVE
TO LOCAL. Only what won is recorded — a resolved conflict shows as the
version that was kept, never as a conflict.

- Click a file to open it in place (`history_change`): FILE, DIFF, COMPARE
  TO CURRENT (only when that version isn't the local file now), HISTORY,
  DOWNLOAD. Click again to close (`history_panel_controller.js`). Images
  show before and after.
- HISTORY is one file's dated log (`history_file`).
- The diff is `SiteSync::VersionPreview`, a Myers diff with a work limit
  (`DIFF_WORK_MAX`). The first version used a longest-common-subsequence
  table and gave up on a real `default.css` change; don't go back to it.
- DOWNLOAD (`history_version`) is inline only for raster images, never SVG.
- Events from before the store existed come from the old
  `sync-history.jsonl` under "Before versions were kept", restorable only
  from local snapshots. They age out.

**Per-file restore was built, designed three times in Figma, and shelved.**
Restoring one file on one side leaves the other side different until the
next sync, and every variant of the screen needed states people would have to
understand (restored here, not yet there; which side; what the next sync
will do). The decision: show what happened, let people open, copy or download
any version, and undo whole syncs only. `SiteSync::VersionRestore` still
exists with no UI; if per-file actions come back, build on it and keep its
rule that only a file's latest change can be acted on. The mocks are in
[specs-parked.md](specs-parked.md#3-sync-history-per-file-restore-and-find-a-file).

### REWIND

REWIND undoes the newest sync: pushed files go back on live, pulled files go
back on local, and **this computer's record of those files goes back too**,
so the two sides are out of sync afterwards and the next sync makes the same
moves again unless someone changes the files first.

- Chosen over "put both sides back to the old version", which was
  rejected as not an undo. Rewinding leaves the site out of sync on purpose:
  check live or local, fix what's needed, then sync.
- **Only the newest un-rewound sync** can be rewound
  (`SiteSync::Rewind.candidate`; rewind and restore events are passed over).
  Rewinding an older sync would mean rewinding everything after it, with
  more ways to go wrong. A per-file "REWIND 1 FILE" was discussed and
  deferred: copy or download covers it.
- Put-back files get their **original modified time** (`before_mtime`).
  With a new time, the next sync would read the rewound side as the change
  and flip the direction, or call it a conflict.
- The confirm page lists ON LOCAL and ON LIVE, and names any file changed
  since the sync. Needs live; changes files only (no database, secrets or
  video originals). The current versions are saved before anything is put
  back. It runs in `SiteSyncRewindJob` on the same status key as a sync, so
  the two can't overlap.
- A rewind resets only **this computer's** record. Live's own record still
  matches live, so each side's self-report says "no change" while the files
  differ. `PeerAgreement` places such files by this computer's record
  (`on_live` / `on_local`, the reconciler's rule), and the Site Sync page
  shows them as live or local changes. Fixing live's record instead would
  need a new live endpoint.

---

## Seeing a change before syncing

Each file under "Show local changes" / "Show live changes" opens in place
(`pending_change`, `_pending_list`, `_pending_panel`): FILE, DIFF, HISTORY,
DOWNLOAD.

- When only one side changed a file, the other side still holds the version
  both last agreed on, so **live now against local now is exactly the change
  the sync will make.** No record is needed.
- Live's copy is fetched on click with `Exchange.download_files` (the pull
  endpoint, so no deploy needed) into a temporary folder
  (`SiteSync::PendingPreview`), never into `site/`. Files over 10 MB aren't
  fetched for a look.
- Roe's docs fold into one row ("Roe documentation — N files changed")
  because an update rewrites dozens at once; the row opens to list its
  files, each of which opens like any other.

---

## Conflicts

A file changed on both sides still stops the sync and asks. This screen
stays on purpose: "newest wins" can lose someone's work, and the person can
see both versions before choosing.

- Each file opens LOCAL | LIVE | DIFF in place (`_conflict_panel`,
  `pending_change?change=conflict`), with live fetched the same way as above.
  The links carry `data-turbo="true"` because the resolutions form around
  them turns Turbo off.
- APPLY CHOICES & SYNC / RESOLVE ALL BY MOST-RECENT & SYNC apply the choices
  and then run the rest of the sync in the same job
  (`SiteSyncConflictResolutionJob`, `then_sync: true`). Before this, the
  resolution settled only the conflicting files and the page still listed
  everything else, which looked like the sync had done nothing. New
  conflicts stop and ask again; nothing loops.
- Keep-both-renamed is still deferred.

---

## Deletions

Deletions propagate, and only a **bulk** deletion stops to ask:
`sync_confirm_deletions_over` defaults to **20**
(`Reconciler::DEFAULT_CONFIRM_DELETIONS_OVER`). `0` asks every time, `never`
never asks.

- It was 0 (ask for every deletion) after a wrong baseline inferred
  deletions that never happened and destroyed 9 episodes and 23 audio files
  (2026-08-26). Every deleted file is now saved first, so a routine deletion
  can be rewound or downloaded, and asking every time only trains people to
  click through.
- The guard stays for that failure: a sync proposing more than 20 deletions
  has usually misread something. It turns the deletions into conflicts the
  existing screen already handles.
- A site's own `site.yml` value overrides the default, so an install that set
  a number keeps it.

---

## Backups and the store

The store took over what the old per-sync snapshots were for, so snapshots
went back to being a backup:

| | Version store | Local snapshots (`backups/local/`) | Live database (`backups/live/database/`) |
|---|---|---|---|
| Made | Every sync, rewind and resolution | Create backup; before restoring a backup | Every sync |
| Holds | Only files a sync changed or deleted | All of `site/` except `db/`, image variants, video web versions | Encrypted live database bundle |
| For | Sync History, REWIND, DIFF | Putting the whole site back (Site Backups tab) | The only backup of production for now |

- **Syncs and resolutions no longer take a local snapshot** (2026-11-13). A
  pull's replaced files are in the store; a full copy of `site/` per pull
  duplicated them. Snapshots stay manual; a schedule is planned.
- The **encrypted live database backup runs on every sync, unchanged.** It
  stays until another backup system covers production.
- **No snapshot before a Roe update.** The update backs up the databases
  (it runs migrations), and otherwise only mirrors `site/documentation/roe/`
  and moves settings keys at boot; neither is someone's own content.
- Snapshots and the store are **not** linked to each other. Once snapshots
  stopped being taken alongside every sync, they rarely hold the same
  version, and the store can't link to `site/`.
- Snapshots still matter for what the store can't do: files no sync touched,
  the whole site at a point in time, and large files' after-sync versions.
  Don't propose retiring them.

---

## Wording

Rules for all Site Sync copy:

- **"changed", never "modified"**, across the Site Sync page, Sync History
  and docs. One word per idea. (Data keys stay `:modified`.)
- **"Sync History"**, capitalised, everywhere it's named (pages, hints,
  docs). A file's own log is "History" (the button) or "File History" (its
  page title).
- **"local" and "live"** — never "yours", "mine", "this machine", or
  possessives like "live's" in the interface. "Keep local", "local is newer".
- REWIND's confirm and finished copy was written by the maintainer; lines
  marked `# COPY:` are the maintainer's to edit.

---

## Live's answer on the Site Sync page

The page draws from live's last answer, which is cached. When that answer is
more than a minute old (`Exchange::REFRESH_STALE_AFTER`), opening the page
asks live again in the background (`refresh_if_stale`). The page then waits
for the new answer (`site_sync_refresh_controller.js`, polling `peer_status`
every 2 seconds for up to 20) and reloads once it arrives. If a field on the
page was edited first, it shows a note instead of reloading over the edit. It
doesn't wait while a transfer runs, because `site_sync_controller.js` reloads
the page when that finishes. REFRESH SYNC STATUS still asks live straight away.

## Old live backup folders

`backups/live/content/<time>/` folders follow the Sync History window
(`sync_history_days`): `Versions.trim!` removes any folder named for a time
before the cutoff, except the newest, which `latest` points at (rsync's
`--link-dest`, `rake site:rollback`). Since 2026-11-13 each sync removes its
own folder once the store has the files, so what's left is older syncs and
`rake site:backup`'s full copies. That task keeps its own newest 15 as well.

---

## Still open

- Live's own sync record isn't rewound (see REWIND).
- A schedule for local snapshots.

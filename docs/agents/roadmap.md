# Direction and status

Where the larger pieces of work stand. Statuses checked against the code on
2026-09-15; treat the code as authoritative if it disagrees.

| Work | Status |
|---|---|
| Ruby 4.0.5 upgrade | **Shipped** |
| Ruby 4.0.10 (security fix) | **Shipped** in 0.5.0 |
| Bi-directional Site Sync over HTTP | **Shipped** |
| Update as redeploy for container hosts | Goal, host-agnostic |
| First-boot bootstrap | Partly shipped (`RoeSecrets::Bootstrap`) |
| Several installs side by side | **Shipped** (Phase 1: registry + `roe` command); admin switcher not built |
| Multi-tenant Roe | Future, not started |
| Open-source the Substack importer | Eventual intent |
| Importer pipeline decomposition | Designed, not built — [specs-parked.md](specs-parked.md) |
| Media usage index rearchitecture | Designed, parked — [specs-parked.md](specs-parked.md) |

---

## The guiding principle

Support time-tested protocols (HTTP, SSH, rsync), make install and deploy as
simple as possible, and keep everything portable — without bending Roe to any
single vendor.

### Do not build a paradigm around one host

Building Roe's install story around one host's template, volume, and variable
system was evaluated and rejected. It is vendor lock-in, and it contradicts the
whole point of the project. A template for any given host can exist the same way
it would for any Docker host — but not by reshaping Roe to fit one.

It also hasn't been shown that hosting friction is the limiting factor, so this is
not a place to over-build.

Roe stays local-first and host-agnostic.

---

## Ruby 4.0.5 — shipped

Done in two releases to protect existing users. The first moved users to mise
while staying on Ruby 3.2.2, and added an updater preflight that blocks an update
whose incoming `.ruby-version` needs a Ruby the user does not have. That preflight
had to ship first, because the updater runs the *old* version's code and so had to
learn to protect the later jump.

The second release made the jump. `current/.ruby-version` is `4.0.5` and the
Gemfile declares `csv` and `ostruct`, which were default gems extracted in Ruby
3.4/3.5 and are no longer auto-loaded — `substack_importer.rb` requires csv,
`post.rb` and `imports_controller.rb` require ostruct. Without them the app fails
at boot with `LoadError: cannot load such file -- csv`.

No application code changes were needed. Only those two gem declarations.

---

## Changing the Ruby version: how each install gets it

`current/.ruby-version` is the one place the Ruby version is set. A release that
changes it (4.0.5 → 4.0.10 in 0.5.0, for CVE-2026-132825, which Brakeman flags)
also changes `ARG RUBY_VERSION` in the `Dockerfile`, the `|| echo` fallbacks in
`roe.sh`, and the version named in `README.md` and `AGENTS.md`. Nothing reads
the Ruby version from the Gemfile, so it isn't pinned there.

How each kind of install picks it up:

- **The in-app updater (user installs).** Handled by
  `RoeUpdater::UpdateOrchestrator`. Right after downloading, `checking_ruby`
  reads `staging/.ruby-version`. If that exact Ruby isn't installed (mise or
  rbenv), the update pauses at `awaiting_ruby` with an Install / Cancel panel;
  nothing is switched or migrated yet. On Install it installs mise if needed,
  sets mise to read `.ruby-version` and to use precompiled Rubies, and runs
  `mise install ruby@<version>` (the global Ruby is left alone). After the
  switch, `installing_gems` and `building_assets` run under the new Ruby
  (`mise exec ruby@<version> --`), so native gems are built for it. The update
  is run by the *old* version's updater, so this only works because every
  release since the 4.0.5 move has had `checking_ruby`.
- **`roe start` / `roe restart` (an install updated with `git pull`).**
  `roe.sh`'s `ensure_app_ruby_and_gems` runs first. If the Ruby in
  `.ruby-version` isn't the one being found, it offers to install it with
  mise (`mise install`, same as the updater), then offers `bundle install` if
  `bundle check` fails, and carries on starting. On restart it runs before the
  server is stopped, so saying no leaves the running server up. The global
  `roe restart` stops and starts in two steps, so it asks first through
  `roe.sh ruby-ready` (only when the install's `roe.sh` has it). With nobody
  at the keyboard it prints the commands and stops. An install the updater
  brought up to date passes both checks without a word. Before this, a pulled
  install quietly kept running on the old Ruby: `mise env -C` only warns about
  a missing version, and the next Ruby on the PATH was used.
- **`./roe.sh check` / a fresh install.** Installs the Ruby with
  `mise use --global` (the installer's path, which also sets the global).
- **Live sites (Fly, Kamal).** Built from the `Dockerfile`, so deploying the new
  release builds an image on the new Ruby.

On a development checkout (a git branch) the updater refuses to run, so after
changing `.ruby-version`: `mise install ruby@<version>`, `bundle install` in
`current/`, the full suite, then `roe restart` (which would also offer both).
Old Rubies stay installed until `mise uninstall ruby@<old>`.

**Precompiled Rubies and older macOS.** Roe sets mise's `ruby.compile false`
(fast, no build tools). mise's precompiled Ruby 4.0.10 for macOS is built on
macOS 26 (`RUBY_PLATFORM` `arm64-darwin25`), and its headers include
`<stdckdint.h>`, which the Command Line Tools for macOS 14 (Apple clang 16)
don't have. Ruby itself runs, but every gem with C code fails to build
(`ed25519` first, reported as "You have to install development tools
first").

The fix is in the Gemfile, because the update to a new Ruby is run by the
*previous* release's updater: the new release's Gemfile is the first code of
the new release that runs (the old updater runs `bundle install` with it).
On macOS, when the running Ruby's `ruby/config.h` has `HAVE_STDCKDINT_H` and
the compiler can't find the header (`echo '#include <stdckdint.h>' | cc -x c
-fsyntax-only -`), the Gemfile puts `lib/compat/` on `CPATH`. Its
`stdckdint.h` maps `ckd_add`/`ckd_sub`/`ckd_mul` to clang's
`__builtin_*_overflow`, which is all Ruby's headers use. Everywhere else the
Gemfile does nothing.

Tested by updating an untouched 0.4.5 install to a 4.0.10 release with its
own (0.4.5) updater and an empty mise: the ready-made Ruby installed, every
native gem built, and the site booted.

Not done this way: building Ruby from source on such Macs. It works (a few
minutes), but an old updater can't be taught to do it, so it only helps
updates after the release that ships it, and it judged a ready-made Ruby
unusable even when the stand-in made it fine, which stopped `roe start`.
Report upstream: jdx/ruby builds macOS Rubies on `macos-26`; building with
`ac_cv_header_stdckdint_h=no` would fix it for every mise user.

---

## Site Sync over HTTP — shipped

The crown jewel of the portability work, and the least host-coupled piece. HTTP is
the universal transport, so content can move between any two Roe instances over
port 443 with no SSH access — which makes changing hosts straightforward.

What exists in `app/services/site_sync/`: `TarArchive` (security-hardened gzip-tar
pack and unpack), `SiteWriter` (mtime restore, guarded deletes), `HttpTransport`
(push, pull, and backup, with hardlink deduplication mirroring rsync's
`--link-dest`), `Exchange` (the HTTP state handshake plus file transfer),
`Ledger`, `Reconciler`, `Checker`, and the `POST /api/site_sync/{download,upload,file_hashes}`
endpoints.

Files over 25 MB (`HttpTransport::PUSH_BATCH_MAX_BYTES`) never go in a batch: a
1.2 GB video in one request died at the proxy on the way up, and on the way down
it took the live server's memory, since the batch tar is built in RAM. They move
in 8 MB pieces instead — `upload_chunk`/`upload_finish`
(`ChunkedUploadsController`) for push, `download_info`/`download_chunk`
(`ChunkedDownloadsController`) for pull and backup. Both sides resume from what
already arrived and check the finished file's SHA-256 before using it. Pieces
wait in `site/.sync-uploads/` (excluded from the Ledger) or, for live backups,
`backups/live/content/.downloads/`, and are cleared after two days.

`sync_transport` defaults to `:http` when unset; rsync is now the explicit opt-out.
`kamal_rsync` (rsync over plain SSH to any box) is already host-agnostic and stays.
`fly_rsync` is Fly-coupled but built, and stays for now; generalising it is a
future goal that the HTTP transport largely obviates.

**Secrets never traverse this channel in either direction.** `Ledger.excluded?` is
public precisely so the unpacker and the endpoint both refuse to write or serve
`system/secrets/` and `db/`. An HTTP backup is therefore content-only and **not**
a key restore. That is by design.

### The conflict model

A conflict means both sides differ from the ledger's last-synced baseline. The
MVP is block-and-resolve, not auto-merge: detect conflicts, stop the sync,
resolve, then proceed. On a true conflict, always prompt — most-recent-wins is a
one-click default in the UI, never silent. Comparison is in UTC. A modified time
on its own says nothing across machines — a file edited at the same moment on
both can carry different times — but every transfer stamps the copy with the
original's time, so a file one sync carried matches exactly on both sides.
That's what the two rules below rely on.

`Reconciler` does a three-way diff of baseline, local, and peer, classifying each
path as push, push_delete, pull, pull_delete, converged, or a conflict
(`EDIT_EDIT`, `EDIT_DELETE`, `DELETE_EDIT`). Content-hash confirmation downgrades
an edit/edit pair with matching bytes to `converged`, so mtime skew does not
produce a false conflict.

**The baseline records only what both sides hold in the same state.**
`Ledger.write_confirmed!` is the one place that writes it after a transfer; the
transfer job, the resolution job and the live side's `refresh_ledger` all go
through it (the resolution job checks its settled paths with
`Ledger.same_state?`). A file missing on the peer stays out, so it reads as a
push rather than a deletion. A file both sides hold in *different* states keeps
its previous entry. That second rule came from a setting saved during a
39-minute pull: the old code recorded the local version as agreed, the next sync
read live's September copy as the change, and pulled it over the newer one. The
symptom was "Content differs from Live site, but neither side reports drift",
which a second sync "fixed" in the wrong direction.

**A sync never replaces a newer copy with an older one unasked.**
`Reconciler.overwrites_newer?` turns a one-way push or pull into a conflict when
the copy being overwritten has a later mtime than the incoming one. A real
change is never older than what it replaces, so this only fires when the
baseline was wrong — it's the net under the rule above.

The Site Sync page reads one answer, `Admin::SiteSyncController#live_sync_overview`,
for both the status line at the top and the "Changes to sync" panel. The top line
once read only the local ledger and said "in sync" while the panel listed files
that differed from live.

The UI is a single "Sync with live" button. A real conflict raises
`ConflictsDetected` and the status becomes `:conflicts` with no overwrite and no
retry; an unreachable peer raises `PeerUnreachable` rather than syncing blind.

**Follow-ups:** keep-both-renamed is deferred, since most-recent plus
keep local/keep live cover the core. Resolution used to apply only the
conflicted files, leaving the rest for another sync; since 0.5.0 it carries on
with the sync in the same run (APPLY CHOICES & SYNC).

What 0.5.0 added on top — the version store, Sync History, REWIND, opening a
change before syncing, comparing both versions in a conflict, the bulk-only
deletion guard, and no snapshot per sync — is in [site-sync.md](site-sync.md).

---

## Update as redeploy for container hosts

On any container image — Fly, Railway, Docker anywhere — `current/` is baked into
the image, so the git-swap the updater performs cannot persist. An update *is* a
new image. The admin should detect the install type and surface "update available,
redeploy."

The only distinction that matters is concrete: **a self-updatable git checkout
versus an immutable image that updates by redeploy.** An earlier "canonical versus
client" framing was rejected as confusing. On any host it is still conceptually an
update and should be labelled as one; only the mechanism underneath differs.

Built host-agnostically for image deploys, this helps Fly today.

---

## First-boot bootstrap

Self-seed secrets and a default site skeleton into an empty volume or directory on
first boot, so any fresh container or VPS deploy works with no manual key
juggling. Host-agnostic.

The secrets half of this exists as `RoeSecrets::Bootstrap` — see
[backups-secrets-and-data.md](backups-secrets-and-data.md), including the guard
that must not be removed.

One diagnostic worth knowing: if the "Generated fresh master.key" warning appears
on *every* boot, the persistent volume is not mounted where `SITE_PATH` resolves.
Each restart is starting with an empty `site/` and regenerating, which means
anything encrypted by a previous boot is no longer decryptable. Fix the mount.

---

## Several installs side by side — shipped (Phase 1)

Several Roe folders run at once, each its own install, tied together by a
registry rather than by one install serving many sites. This was chosen over
multi-tenancy (below) because it gets most of the benefit for a fraction of the
risk and does not rule multi-tenancy out later.

**Where it lives.** `roe.sh register` / `unregister`, `roe.sh start --daemon`,
and `bin/roe` (the global command, copied to `~/.roe/bin/roe`). Registry is
`~/.roe/installs/<name>.conf`, plain `KEY=value` (`NAME`, `ROOT`, `HOST`,
`PORT`), read with `sed`, never sourced. It lives outside every install because
the updater replaces `current/` wholesale.

**Decisions that are easy to undo by accident:**

- The name is the slugified folder basename (`The Briefcase` → `the-briefcase`),
  matching what the Site Sync handshake already uses as an install's identity.
  It is stored at registration, not recomputed, so changing the slug rules later
  cannot silently move a site.
- Each install gets its own hostname, `<name>.roe`, via one `/etc/hosts`
  line. This exists to fix a real bug, not for looks: cookies are per host, not
  per port, so two installs on `localhost` share a jar and sign each other out.
  It only works because neither session cookie sets `domain:` — see
  `docs/11-members-authentication.md`. `config.hosts` in development allows the
  whole `*.roe` suffix.
- `roe.sh` exports `ROE_HOST` when registered; `development.rb` prefers it for
  mailer URLs. Magic-link sign-in makes a wrong mailer host a login to the wrong
  site.
- Ports are fixed per install at registration (first free from 3000 across the
  registry), so URLs are stable. If an unrelated app holds the port at start
  time, `resolve_port_collision` still shifts for that run only.
- The global `roe` never boots a site itself. It shells out to that install's
  own `roe.sh`, so an old install keeps booting with the logic it shipped with.
- `roe` reads the registry and PID files directly. It deliberately does not use
  `SiteSync::Exchange`, which is single-peer and whose token grants full
  `/download` and `/database` access.

**Known limits.** Memory is the ceiling — one Puma per site. Switching is
separate logins per install (each has its own `User` table), not single
sign-on. On WSL the browser reads Windows' hosts file, so the user adds the
line there by hand; `register` prints it.

**Not built.** Phase 2 (read-only site switcher in the admin) and Phase 3
(start/stop siblings from the admin, deferred on security grounds). A reverse
proxy on :80 routing by `Host` would remove ports from URLs entirely and is
worth revisiting.

---

## Multi-tenant Roe

A single install (`current/` plus one gem set) serving many site folders under
`sites/`, replacing today's single `site/`. `RoeSitePaths::SITE_PATH` is currently
singular.

**Future direction, not started, on hold.** Do not assume it when working on
current code.

It matters for one decision: it is the prerequisite for vendoring gems into the
Roe folder. `bundle config set --local path vendor/bundle` was discussed and
deferred, because per-`current/` vendoring fights the versioned update model —
every update would recompile all native gems — and duplicates gems. Multi-tenancy
removes the duplication objection, since one gem set would serve every site, so
revisit vendoring then, ideally alongside a Ruby upgrade (gems are
Ruby-version-specific).

If a self-contained or clean-uninstall need comes up before then, the lighter
answer was a `./roe.sh uninstall` that removes the folder and offers
`mise uninstall ruby@X`.

---

## Open-source the Substack importer

The importer works end to end and is reusable beyond Roe, so it may eventually be
extracted as a standalone project. Not a near-term task, but it is the reason to
keep the decomposition clean: Substack should be just another source adapter on a
generic pipeline, which is what makes it cleanly extractable.

So favour separating Substack-specific logic — CSV and ZIP parsing, HTML cleanup
filters, paywall handling — from the generic ingest machinery.

See [specs-parked.md](specs-parked.md) for the pipeline design.

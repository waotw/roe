# Direction and status

Where the larger pieces of work stand. Statuses checked against the code on
2026-09-15; treat the code as authoritative if it disagrees.

| Work | Status |
|---|---|
| Ruby 4.0.5 upgrade | **Shipped** |
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
one-click default in the UI, never silent. Comparison is in UTC, because mtime
alone cannot be trusted across machines or after a copy.

`Reconciler` does a three-way diff of baseline, local, and peer, classifying each
path as push, push_delete, pull, pull_delete, converged, or a conflict
(`EDIT_EDIT`, `EDIT_DELETE`, `DELETE_EDIT`). Content-hash confirmation downgrades
an edit/edit pair with matching bytes to `converged`, so mtime skew does not
produce a false conflict.

The UI is a single "Sync with live" button. A real conflict raises
`ConflictsDetected` and the status becomes `:conflicts` with no overwrite and no
retry; an unreachable peer raises `PeerUnreachable` rather than syncing blind.

**Two follow-ups that remain open:** keep-both-renamed is deferred, since
most-recent plus keep-mine/keep-live cover the core; and resolution applies only
the conflicted files, so the sync needs running again afterwards to flow the safe
push and pull sets that the block skipped.

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

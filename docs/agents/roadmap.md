# Direction and status

Where the larger pieces of work stand. Statuses checked against the code on
2026-09-15; treat the code as authoritative if it disagrees.

| Work | Status |
|---|---|
| Ruby 4.0.5 upgrade | **Shipped** |
| Bi-directional Site Sync over HTTP | **Shipped** |
| Update as redeploy for container hosts | Goal, host-agnostic |
| First-boot bootstrap | Partly shipped (`RoeSecrets::Bootstrap`) |
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

The Railway one-click-template idea was explored twice and shelved both times.
Reshaping Roe around one proprietary host's template, volume, and variable system
is vendor lock-in, which contradicts the whole point of the project. **Do not
re-pitch Railway as a special path.** A Railway template could exist someday like
any other Docker host, but never by bending Roe to fit it.

It is also unvalidated that hosting friction is even a bottleneck — there are too
few users yet to know — so this is not a place to over-build. The cheap
alternative that was agreed: offer Fly free trials at the maintainer's expense,
with no change to the paradigm and a toggle to turn it off.

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

Ben wants to release the Substack importer as its own project eventually. Not a
near-term task. It works end to end and is reusable beyond Roe.

This is the motivating reason to keep the importer decomposition clean: Substack
becomes just another source adapter on a generic pipeline, which is what makes it
cleanly extractable. Favour separating Substack-specific logic — CSV and ZIP
parsing, HTML cleanup filters, paywall handling — from generic ingest machinery.

See [specs-parked.md](specs-parked.md) for the pipeline design.

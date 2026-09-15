# Backups, secrets, and member data

Status: **shipped**. Verified against the code on 2026-09-15 —
`current/app/services/site_sync/` holds the implementation and `backups/` exists
at the project root.

This is the area where a mistake has already cost a live site its encryption
keys. The guards described here exist because of specific incidents; please do
not simplify them away.

---

## Where secrets live

**Per-install Rails secrets** — `master.key` and `credentials.yml.enc` — live in
`site/system/secrets/` (`RoeSitePaths::SITE_SYSTEM_SECRETS_PATH`). They are
carried by site backups, excluded from Site Sync, and so never mismatch on
update. `credentials.yml.enc` is gitignored at source: each install generates its
own during setup, because shipping one developer's encrypted credentials to other
installs creates a `master.key` mismatch on every update.

**Integration credentials** — Stripe, Postmark, and similar — are stored as
encrypted attributes on database rows, not as files. Each integration has an
ActiveRecord-backed config model declaring `encrypts :field_name`. The encryption
key is the Active Record encryption primary key, which does live in the encrypted
credentials, but the ciphertext values sit in database columns.

When adding an integration that needs a secret, follow that pattern. Do not add a
new file under `site/system/secrets/` — that location is only for Rails bootstrap
material (`master.key`, `secret_key_base`, the Active Record encryption keys
themselves).

One exception worth knowing: **Snipcart no longer stores a secret at all.** Its
store runs on a public client-side snippet and its webhooks are validated by
token, so `SnipcartConfig` has no `encrypts` and is deliberately absent from
`RestoreCheck::PROBE_MODELS`.

Test keys for integrations are kept in YAML under `site/system/integrations/`;
live keys are encrypted in the database and environment-specific.

---

## The boot secret bootstrap, and the guard you must not remove

`RoeSecrets::Bootstrap.run!` (in `lib/roe_secrets/bootstrap.rb`, called from
`config/application.rb`, tested in `test/lib/roe_secrets/bootstrap_test.rb`) seeds
`master.key` and `credentials.yml.enc` before Rails reads them. It is required
with `require_relative` rather than autoloaded, because it runs before Zeitwerk
is ready.

### The incident

On a live site, a database restore installed an empty `master.key` over the good
one. The old inline bootstrap then could not decrypt `credentials.yml.enc`, fell
into its "seed a fresh secret_key_base" branch, and **rewrote the credentials —
dropping the `active_record_encryption` keys** (508 bytes down to 260). Every post
returned a 500 with `Missing Active Record encryption credential:
active_record_encryption.primary_key`. Recovery meant restoring the
`.pre-restore-<timestamp>` key and credentials pair together.

### The guard

If `credentials.yml.enc` is present and non-empty but `read` comes back blank —
wrong or empty `master.key`, a `RAILS_MASTER_KEY` mismatch, corruption — bail
with `:unreadable` and **change nothing**.

Never overwrite credentials that cannot be decrypted. Doing so destroys the
Active Record encryption keys permanently. Bailing makes the boot fail loudly on
the real key error, which is fully recoverable: fix the key, and the credentials
are intact.

### The later self-heal

A follow-up fix (shipped) handles a different case: an install old enough that its
credentials predate Active Record encryption has a valid `master.key` and
readable credentials that simply lack the keys. Originally the keys were seeded
only when `master.key` had just been generated in the same run, so these installs
never healed and crashed on the first `encrypts` save.

Now the keys are seeded whenever they are absent from readable credentials. This
is safe for three independent reasons: undecryptable credentials already returned
`:unreadable` earlier; seeding requires both the decrypted config and the YAML
about to be written to show no `primary_key`; and absent keys mean nothing was
ever encrypted with them.

### The Kamal nuance behind all of this

On a Kamal droplet the real master key comes from the `RAILS_MASTER_KEY`
environment variable, and the on-disk `master.key` file is an empty decoy. The
disaster-recovery bundle therefore captured and restored an empty key file. That
is precisely why a restore must never naively swap key files.

---

## On-disk backup layout

Under the project root, via `SiteSync::BackupPaths`:

- `backups/local/<timestamp>/` — full `site/` content snapshots, using rsync plus
  hardlinks. The "Local" tab in the UI. Managed by `BackupManager`.
- `backups/live/database/<timestamp>.enc` — encrypted live-database recovery
  bundles, captured every sync, retention 15. The "Live Site" tab.
  `SiteSync::DatabaseBackup` on the pull side,
  `BackupManager.build_encrypted_db_bundle` on the production side.
- `backups/live/content/` — pre-push safety snapshots of live content. Internal;
  not surfaced in the UI.

A boot migration in `config/application.rb` moves the legacy
`site_backups/{local,production}` layout to `backups/{local,live/content}`. It is
idempotent and leaves stray files behind.

Content snapshots no longer carry the database, and the database is no longer
written to `site/db`.

Note that the updater has its **own, separate** backup system,
`RoeUpdater::BackupManager`. Its on-server rollback backups are deliberately not
encrypted — the plaintext database sits next to them anyway, and encrypting would
force someone to supply a passphrase just to roll back.

---

## Encrypted database in portable backups

The policy is **always encrypt, with no feature flag**, and one hard rule: *the
plaintext production database never leaves the host.*

A database is included in a backup if and only if a backup passphrase is set. No
passphrase means the backup omits the database, which is safe. This never forces
a passphrase and never ships plaintext. The members and store features only
*nudge* the admin to set one; that nudge is not a security gate. An earlier idea —
plaintext when no sensitive features are in use — was rejected, because the
database always holds owner secrets: deploy secrets, two-factor recovery codes,
the admin password hash, and the encrypted integration tokens.

The live database stays plaintext so that background jobs, public member
authentication, and webhooks keep working with no admin present.

The database is **not** drift-synced. It is pulled whole and encrypted as a
distinct second phase of every sync — best effort, isolated, and never able to
fail the content sync. One direction only: production to laptop. The ledger still
excludes `db/`.

The passphrase is an encrypted attribute on `SyncConfig#backup_passphrase` and
must be reachable by production, which stages the blob before serving it. It is a
convenience copy, **not** a recovery key — the admin must save it somewhere else,
since it is locked inside the very backup it protects. Losing it means losing the
members in that backup, not the site.

Components: `SiteSync::BackupCrypto` (AES-256-GCM, PBKDF2-SHA256 at 210k
iterations, blob layout `MAGIC(6)|salt|iv|ciphertext|tag`, streaming,
tamper-evident, atomic), `BackupManager#stage_encrypted_db!` /
`#include_encrypted_db_in` / `#restore_db`, the `POST /api/site_sync/database`
endpoint which streams ciphertext only, and `SiteSync::DatabaseBackup.pull!`.

---

## Restore is database-only, and why

After the key-loss incident above, restore was redesigned so it **never**
auto-swaps encryption credentials.

The flow: an admin uploads the `.enc` bundle to the live admin over HTTPS.
`SiteSync::PendingRestore.stage_from_upload` stages the database as
`<db>.restore-pending` and **parks** the bundle's credentials as
`<key>.from-backup` — extracted, not installed. At the next boot an inline block
in `config/application.rb` swaps the database only, keeps the previous one as
`.pre-restore-<timestamp>`, clears stale wal and shm files, and drops a plaintext
`.restore-check-needed` marker.

Sessions live in the database, so any restore signs everyone out.

Transport is an authenticated admin file upload over HTTPS — not SSH, not the
sync token. That works on any host without SSH setup, and it keeps the machine
token channel clear, preserving the property that a leaked token cannot write the
database. The ciphertext travels and production decrypts on its own disk, so
plaintext never crosses the wire and the passphrase acts as a second factor.

**The self-check.** `SiteSync::RestoreCheck`, run from an
`Admin::BaseController` before_action and gated by the marker, probes an
encrypted column. If it cannot be read, it writes a
`.restore-credentials-mismatch` marker. All markers live next to the database and
are never encrypted, so they survive a boot where encryption itself is broken.

**Guided recovery.** When a mismatch is flagged and parked credentials exist, the
Site Sync page offers "Apply backup credentials." Applying sets a marker; the next
boot installs the parked pair, validates it (it must decrypt to an Active Record
primary key), and **automatically reverts** to the previous working pair if
validation fails, surfacing a banner. Restart instructions come from the peer's
folder name, deploy target, and rails subdirectory, synced into the plaintext
`SyncConfig#peer_env` fields, with a generic fallback.

**On Fly this is gated off entirely.** Fly's Active Record keys are `AR_ENCRYPTION_*`
environment secrets rather than credential files, so a bundled `master.key` is a
decoy and applying it would validate-fail and revert. Both the credential-apply
boot block and the controller action check `ENV["FLY_APP_NAME"]`. The recovery
banner instead tells the operator to re-push keys from local with
`bin/rails roe:fly:sync_secrets APP=<app>`. A Fly machine cannot set its own
secrets — that needs external flyctl authentication — so key recovery is
operator-run by design. Fly is also single-machine, so a database restore only
lands on the machine you upload to.

---

## Member data is plaintext, deliberately

`members.email`, `name`, and `pending_email` are stored **unencrypted**. The
schema has `t.string "email"` with a unique index on the plaintext column, and
`Member` declares no `encrypts` or blind index. (`email_confirmation_token` is a
change-confirmation token, unrelated.)

SQLite has no login. The file is readable by anyone who has it; filesystem
permissions and disk encryption are the only guards, and neither helps once the
file is copied off the machine.

**Why plaintext, for now.** Two reasons. First, it is the standard Rails default,
because email has to stay queryable — unique index, find-by-email at login and
confirmation, deduplication on import. Second, and specific to Roe: encrypting
email with `deterministic: true` would preserve the index and equality lookups
but would couple the database to the keys in `system/secrets/`, which are
deliberately not synced. A database pulled to a laptop would become unreadable
without the matching key, which trades directly against the disaster-recovery
property Roe wants to keep — host destroyed, but members still recoverable from a
portable copy.

Plaintext is portable but exposed. Encrypted is safe at rest but key-bound. The
project chose portable.

**Do not add member PII encryption without reopening this trade-off explicitly.**
If it is revisited, it needs `encrypts :email/:name/:pending_email, deterministic: true`,
a data migration for existing rows, and a foolproof way to keep the key with the
backup. Until then the mitigation is operational: encrypted disks, do not leave
pulled database copies lying around, restrict who can pull.

Note that encrypting the database inside portable backups (above) supersedes most
of the pressure for field-level email encryption — the live database stays
plaintext, the copies that leave the box do not.

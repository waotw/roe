# Roe Development Workflow

**Status:** Pre-1.0 (0.x)
**Audience:** Roe maintainers & contributors — internal, not part of the public site docs.

Roe develops in the open on Codeberg ([`waotw/roe`](https://codeberg.org/waotw/roe)). This document covers how versions are tagged, how the branch/release flow works, and how the in-app update system consumes it.

Push/PR access to `development` and `main` is invite-only (trusted contributors). If you don't have it, reach out first — outside contributions are handled case-by-case.

---

## Versioning & Release Tagging

Roe follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`, with an optional pre-release suffix. Tags are always `v`-prefixed (`v0.1.0`).

We're pre-1.0, so the working cadence is `0.MINOR.PATCH`:

- **`0.MINOR.0`** — new features / notable changes (e.g. `0.1.0 → 0.2.0`)
- **`0.x.PATCH`** — bug fixes, safe to update (e.g. `0.1.0 → 0.1.1`)

### Pre-releases are anchored to their target version

A pre-release points **at** the version it's leading to — it never advances the number past it. Every build for the next release shares that target version and is distinguished by a counter:

```
v0.1.0-nightly.1     ← testing builds toward 0.1.0
v0.1.0-nightly.2
v0.1.0-nightly.3
v0.1.0-rc.1          ← "shipping as 0.1.0 unless a bug turns up"
v0.1.0               ← final; suffix dropped
v0.2.0-nightly.1     ← next cycle begins
```

This is the whole point: the version number stops running ahead of stable, and release notes for a version are simply everything tagged `vX.Y.Z-*`.

### The stability ladder

| Stage | Where | For | Stability |
| --- | --- | --- | --- |
| bleeding edge | the `development` branch (no tag) | developers | may break |
| nightly | `vX.Y.Z-nightly.N` | testers / the `nightly` update channel | the accumulating beta of the next release |
| release candidate | `vX.Y.Z-rc.N` | final testing | frozen; shipping unless bugs turn up |
| stable | `vX.Y.Z` | everyone | released |

`nightly` and `rc` sort in that order for free — SemVer compares the pre-release identifiers, and `nightly` < `rc` < final. (If you ever add a third stage it must sort correctly too. The classic ladder is `alpha` < `beta` < `rc`; note "beta" sorts *before* "nightly", so those two don't mix — pick one convention.)

### Tagging rules (the update system depends on these)

- **Always put a dot before the counter:** `v0.1.0-nightly.10`, never `-nightly10`. With the dot the counter sorts numerically (`10 > 2`); without it, it sorts lexically and `nightly10` lands *before* `nightly2`.
- **Tags must be `v`-prefixed.** VersionChecker ignores a tag pushed without the `v` (e.g. `0.1.0`), and the downloader clones by the `v`-tag.
- **You don't bump `VERSION` per pre-release.** Updates are decided by tags, and the installer writes the `VERSION` file from the tag it installs (`write_version_files` is deliberately authoritative — a stale committed `VERSION` is corrected on update). The committed `VERSION` only self-reports for *dev installs* and `roe.sh status`, so bump it at the **final release** (and optionally to the target at the start of a cycle). See [Cutting a Release](#cutting-a-release-maintainer).
- **Pre-releases retire themselves.** A pre-release is only offered while it outranks the latest stable. Once `v0.1.0` ships, its own `-rc`/`-nightly` tags stop being offered; `v0.2.0-nightly.1` keeps being offered because it outranks `0.1.0`.

### How this maps to update channels

The update system treats any tag with a `-` suffix as a pre-release and routes it by install type / channel:

- **User install, `stable` channel (default):** sees only final `vX.Y.Z` tags.
- **User install, `nightly` channel** (`update_channel: nightly` in `site.yml`): also sees the latest pre-release.
- **Dev install** (a git *branch* checkout of Roe itself, rather than a detached-HEAD tag clone): implicitly sees pre-releases — no setting needed.

*Internals: `RoeUpdater::VersionChecker` — `tag_is_prerelease?` keys on the `-`; `pick_latest`/`compare_versions` order tags via `Gem::Version`, which rewrites `-nightly.1` → `.pre.nightly.1` and sorts it correctly. Locked down by `test/services/roe_updater/version_checker_test.rb`.*

---

## Branch Strategy

Roe uses a git-flow style: a long-lived integration branch feeds released code into `main`. Releases are **tags**, not long-lived branches.

| Branch | Purpose |
| --- | --- |
| `main` | Released code only — every commit is a tagged release. Never committed to directly. |
| `development` | Integration branch for the next release. The bleeding edge — what dev installs track. |
| `feature/<name>` | A single feature. Branched from `development`, merged back, deleted. |
| `fix/<name>` | A single bug fix headed for the next release. Same lifecycle. |
| `documentation/<name>` | Docs-only work. Same lifecycle. |
| `hotfix/<name>` | An urgent fix to the *current release* that can't wait for `development`. Branched from `main`, shipped as a patch, then merged back into **both** `main` and `development`. |

`main` and `development` are the only permanent branches; everything else is short-lived.

> Maintaining several older release *lines* with back-ported patches is a **post-1.0 concern** — not needed while there's a single active line. (Crucial security fixes still reach older/lapsed installs; see [User Update System](#user-update-system).) Revisit branch-per-line once older versions have real users to support.

---

## Backwards Compatibility

The north star: **updates should be safe** — content, themes, and sites keep working across updates. Breaking changes are avoided; when genuinely necessary they'll be well-tested (with migrations where possible), announced ahead of time, and clearly communicated. It's a goal, not a promise of 100% forever — but it's the bar.

---

## Contributor Workflow

1. Branch from `development`:
   ```bash
   git checkout development && git pull
   git checkout -b feature/short-description   # or fix/... or documentation/...
   ```
2. Make the change with tests, then commit (reference the issue):
   ```bash
   git commit -m "Add: short description

   Fixes #123"
   ```
3. Push and open a pull request against `development`.

(An urgent fix to the *current release* is the exception — branch it from `main` as `hotfix/...`; see below.)

**Requirements:** tests for the change, docs updated for user-facing changes, all tests passing, one change per PR.

---

## Cutting a Release (maintainer)

Pre-releases are tagged on `development` (they're builds toward the next version). The final is tagged on `main` after merging.

**A nightly / rc — on `development`:** just tag the current commit. No `VERSION` bump — the installer sets it from the tag (see the tagging rules above).

```bash
git checkout development && git pull
bin/rails test
git tag v0.2.0-nightly.3        # tags current HEAD
git push origin development v0.2.0-nightly.3
```

Repeat per build (`-nightly.4`, then `-rc.1`, …), incrementing the counter.

**The final release — merge to `main` and tag there:**

```bash
git checkout main && git pull
git merge --no-ff development           # bring the release into main
# Bump VERSION here — this is the one that matters: `version: 0.2.0`
git commit -am "Release v0.2.0"
git tag v0.2.0
git push origin main v0.2.0
git checkout development && git merge main   # keep development current
```

Gather release notes by diffing from the previous stable:

```bash
git log v0.1.0..v0.2.0     # everything landed since the last release
```

**A hotfix — a patch to the current release, branched from `main`:**

```bash
git checkout main && git pull
git checkout -b hotfix/short-description
# fix + test, then set VERSION to the patch: `version: 0.2.1`
git commit -am "Fix: short description (v0.2.1)"
git checkout main && git merge --no-ff hotfix/short-description
git tag v0.2.1
git push origin main v0.2.1
git checkout development && git merge main   # so the fix isn't lost on the next release
```

> **The update system is branch-agnostic — it only reads tags.** A nightly tagged on `development` and a final tagged on `main` are both just tags to VersionChecker, and the downloader clones by tag name, so where a tag lives has no effect on updates. Branch structure is purely a maintainer convenience.

---

## User Update System

Roe ships an in-app updater:

1. **Check** — polls Codeberg tags, compares them to the install's `VERSION`, and surfaces an available update in the admin UI (respecting the install's channel).
2. **Apply** — downloads the target tag to `staging/`, runs migrations/tests, atomically swaps `current/` ↔ `staging/`, and restarts.

Update visibility is gated by license:

- **Active license:** all updates (patch, minor, major).
- **Lapsed license:** patch updates on the current minor line, until renewed — **plus crucial security fixes, which are always provided, even for older versions.**

---

## License

Roe is free to use locally; commercial use and commercial site deployments require a license. The full source is public — transparency matters — and enforcement is mostly an honor system. Please support this project if you get use out of it. Full license details here: [LICENSE](https://go-roe.com/license).

# Conventions

Conventions for working on Roe. Most of these came out of a real incident, so the
reasoning is included — that is usually the part which stops someone breaking it
again.

Most share the same shape: **prepare the change, but don't run the step that
mutates state.** Write the migration, draft the commit message, stage the edit —
then hand it over.

---

## 1. Don't run git commands that change state

Unless asked for that specific action, don't run `git add`, `git commit`,
`git push`, `git branch`, `git checkout`, `git switch`, `git merge`, `git reset`,
`git rebase`, or `git remote add/rename/set-url`.

Read-only git is always fine and encouraged: `status`, `diff`, `log`, `show`,
`ls-remote`, `branch --list`.

**Why:** Commits are a human decision. Roe's history is small and readable, and
it stays that way by having a person choose what lands and when.

**How to apply:** When asked to "commit," write the commit message as text, ready
to paste, and let a person run git. A one-off authorisation applies only to that
request and expires immediately after.

Commit messages follow the conventional-commits format — see
[conventional-commits.md](../conventional-commits.md).

---

## 2. Never edit anything under `site/` without being asked

`site/` and everything beneath it — `posts/`, `pages/`, `media/`, `theme/`,
`system/`, `documentation/` — is deliberately not tracked in git.

**Why:** There is no `git restore`. Anything written, overwritten, or deleted
there is gone permanently.

**How to apply:** Reading is fine. Before any write or delete on a path
containing `site/`, either wait to be asked for that specific change, or ask and
get confirmation. Ask even when the request seems to imply it.

**Two hard-won corollaries:**

- **Read the whole file before overwriting it.** Frontmatter alone is not enough
  to confirm identity. Without git, the only way to undo an overwrite is from a
  copy made by reading. This came up on a documentation page where only the
  frontmatter had been read; the body was unrecoverable afterwards.
- **Never run a destructive operation against `site/` as a test.** A smoke test
  for an integration once called `clear_test_config`, which deleted a live
  config file under `site/system/integrations/`.

**Two standing exceptions**, both for requested work only:

- `site/theme/*.css` — CSS work. See [authoring-map.md](authoring-map.md).
- `site/documentation/` — documentation work. Same file.

Everything else under `site/` still needs a question first.

---

## 3. Never run a migration without asking

Do not run `db:migrate`, `db:rollback`, `db:test:prepare`, or apply or revert any
schema change — not even in development.

**Why:** A development database usually holds real content. Running a migration
under a live dev server also leaves it in a half-stale state, which produced a
confusing bug where saves appeared not to persist — the kind of symptom that
costs an hour to trace back to its cause.

**How to apply:** Writing the migration file is fine. Stop before running it. Say
it is ready and let a person run it and restart the server.

---

## 4. Be conservative with the admin editor JavaScript

Do not modify existing Stimulus controllers on the admin editor pages —
especially `editor_controller.js`, `metadata_editor_controller.js`,
`audio_player_controller.js`, and `media_field_controller.js` — unless there is
no alternative.

**Why:** These pages carry many interlocking behaviours (the
publish modal, status-change triggers, the guard that stops Enter submitting the
form, media validation, audio duration extraction), and small changes cascade.

**How to apply:** Read the existing controllers in full first. Prefer adding a
new, isolated controller or partial that composes with what's there. Propose the
smallest additive change before writing it. When unsure, ask.

Also relevant: `layouts/editor.html.erb` sets `turbo-visit-control: reload` so
the unsaved-changes guard fires on navigation. Do not remove that meta tag.

---

## 5. No comments in YAML config files

No `#` comment lines in the kit templates under `current/lib/site_templates/**`
or in the generated configs under `site/system/**`.

**Why:** The config migrations and the admin form both write comment-free YAML
via `YAML.dump`, so hand-added comments create inconsistency.

**How to apply:** Put explanatory text in the admin config schema
(`field_config[:hint]`), which already surfaces it in the settings UI.

**One caveat:** a `#` inside a YAML block scalar — for example within
`product_button_template: |` — is markdown content, not a comment. Leave those
alone.

---

## 6. Write in plain language

No industry jargon in explanations, documentation, or task titles. Say "test it
first" rather than "spike it".

**Why:** People read and act on this text directly. A term the reader has to look
up costs time and adds nothing.

**How to apply:** Name the action rather than the practice. Keep code identifiers,
file paths, and error strings exact — precision about code is wanted. This is
about process vocabulary, not accuracy.

There is a `writing-clearly-and-concisely` skill in `.agents/skills/` for prose
work.

---

## 7. Put theme CSS in the section it belongs to

Both `bare.css` and `default.css` are organised into feature sections marked with
banner comments like `/* ======== MEMBERS ======== */`. New rules go inside the
matching section, never appended to the end of the file.

**Why:** The themes are meant to be read and edited by people building their own.
Someone looking for the member-area styles should find all of them together. A
rule at the end of the file is effectively hidden, and the file degrades into an
unordered pile as features are added.

**How to apply:** Grep for the section banners first —
`grep -n "=====" site/theme/bare.css` — and insert into the matching one. Add a
new section only if nothing fits, following the existing banner format. The two
files stay structurally parallel.

Appended blocks have had to be moved into the right section by hand more than
once. Which file is live is set by `theme.active` in `site/system/global/site.yml`
— see [authoring-map.md](authoring-map.md).

---

## 8. Never rename or move a file or config key that Roe put in `site/`

`site/` travels between installs by Site Sync, and the two sides may be on
different versions. A rename made by new code is pushed to live as a delete
plus an add, and the old code on live no longer finds the file it expects.

**Why:** Site Sync ships content, not code. The live site runs the previous
release until you deploy, and it has to keep working on whatever `site/` the
new release writes. This broke a live site when `search.js` moved into
`javascript/roe/`: local booted on the new code, renamed the old copy in
place, and the next sync carried that rename to a live site still looking for
`javascript/search.js`.

**How to apply:** add, don't move. A new location for something Roe owns is a
*new* file; the old one stays where it is until the release after next. A
config key that has to move is read from both places and still written to the
old one. A one-time migration that renames things under `site/` is not
acceptable, however tidy it looks — there is no way to teach the old code on
live about it.

The Roe-owned folders (`documentation/roe/`, `javascript/roe/`) exist so that
adding to them never collides with the user's files. Use them, and never rename
what is already inside.

This is a beta rule, not the finished design. Before 1.0 the answer is a
pattern like the theme update system's — Roe notices a shipped file has
changed, tells the user, and lets them choose — rather than moving things
underneath a running site. Until that exists, the rule stands as written.

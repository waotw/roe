# Working agreements

Standing rules for anyone working on Roe. Each one came from Ben correcting an
agent, usually after something was lost or broken. Treat them as binding
instructions, not preferences.

The shape of most of these is the same: **prepare the change, but never run the
step that mutates state.** Write the migration, draft the commit message, stage
the edit — then stop and hand it over.

---

## 1. Never run a git command that changes state

Do not run `git add`, `git commit`, `git push`, `git branch`, `git checkout`,
`git switch`, `git merge`, `git reset`, `git rebase`, or `git remote add/rename/set-url`.

Read-only git is always fine and encouraged: `status`, `diff`, `log`, `show`,
`ls-remote`, `branch --list`.

**Why:** Ben controls his own commits. He has asked for this repeatedly, and once
emphatically: "Don't ever commit for me, ever."

**How to apply:** When asked to "commit," write the commit message as text, ready
to paste, and let him run git. A one-off authorisation ("you can commit this
time") applies only to that request and expires immediately after.

**No attribution trailer.** Leave `Co-Authored-By: Claude ...` off every commit
message, including every message in a multi-commit set. This has had to be asked
for more than once.

Commit messages follow the conventional-commits format — see
`docs/conventional-commits.md`.

---

## 2. Never edit anything under `site/` without explicit permission

`site/` and everything beneath it — `posts/`, `pages/`, `media/`, `theme/`,
`system/`, `documentation/` — is deliberately not tracked in git.

**Why:** There is no `git restore`. Anything written, overwritten, or deleted
there is gone permanently.

**How to apply:** Reading is fine. Before any write or delete on a path
containing `site/`, either wait for Ben to ask for that specific change or ask
and get confirmation. Ask even when the request seems to imply it.

**Two hard-won corollaries:**

- **Read the whole file before overwriting it.** Frontmatter alone is not enough
  to confirm identity. Without git, the only way to undo an overwrite is from a
  copy made by reading. This came up on `site/documentation/payments.md`, where
  only the first five lines had been read and the body was unrecoverable.
- **Never run a destructive operation against `site/` as a test.** A Snipcart
  smoke test once called `clear_test_config`, which deleted
  `site/system/integrations/snipcart.yml`.

**Two standing exceptions**, both for requested work only:

- `site/theme/*.css` — CSS work. See [authoring-map.md](authoring-map.md).
- `site/documentation/` — documentation work. Same file.

Everything else under `site/` still needs a question first.

---

## 3. Never run a migration without asking

Do not run `db:migrate`, `db:rollback`, `db:test:prepare`, or apply or revert any
schema change — not even in development.

**Why:** Ben was angry about this: "Don't fucking apply migrations without
checking with me first, ever!" Running one under his live dev server also left it
in a half-stale state that produced a confusing bug where saves appeared not to
persist. His development database holds real data.

**How to apply:** Writing the migration file is fine. Stop before running it.
Tell him it is ready and let him run it and restart his server.

---

## 4. Never touch the Obsidian vault

Do not read, search, or modify `~/Dropbox/-OBSIDIAN/`. This includes sweeping it
with grep or find while hunting for a note.

**Why:** It is Ben's personal thinking space, not project material. An agent once
searched it uninvited while looking for a lost plan. He had mentioned Obsidian
only as a place *he* had already looked, which is not an invitation.

**How to apply:** If a note might live there, say so and ask him to look.
Basecamp and the repository are fair game; the vault is not.

---

## 5. Be conservative with the admin editor JavaScript

Do not modify existing Stimulus controllers on the admin editor pages —
especially `editor_controller.js`, `metadata_editor_controller.js`,
`audio_player_controller.js`, and `media_field_controller.js` — unless there is
no alternative.

**Why:** Ben's words: "Be careful not to mess up any existing JS, there's a lot
going on with this page." These pages carry many interlocking behaviours (the
publish modal, status-change triggers, the guard that stops Enter submitting the
form, media validation, audio duration extraction), and small changes cascade.

**How to apply:** Read the existing controllers in full first. Prefer adding a
new, isolated controller or partial that composes with what's there. Propose the
smallest additive change before writing it. When unsure, ask.

Also relevant: `layouts/editor.html.erb` sets `turbo-visit-control: reload` so
the unsaved-changes guard fires on navigation. Do not remove that meta tag.

---

## 6. No comments in YAML config files

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

## 7. Write in plain language

No industry jargon in explanations, cards, or task titles. Ben asked what a
"spike" was; say "test it first" instead.

**Why:** He reads and acts on this text directly. A term he has to look up costs
him time and adds nothing.

**How to apply:** Name the action rather than the practice. Keep code identifiers,
file paths, and error strings exact — precision about code is wanted. This is
about process vocabulary, not accuracy.

There is a `writing-clearly-and-concisely` skill in `.agents/skills/` for prose
work.

---

## 8. Put theme CSS in the section it belongs to

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

Ben has twice had to move appended blocks into the right section by hand.

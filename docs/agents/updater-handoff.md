# Updater hand-off: each release installs itself

**Status: built for 0.5.1** (not yet released). Code:
`app/services/roe_updater/handoff.rb` (frozen once shipped), `bin/update`
(each release's own steps), `app/services/roe_updater/stuck_update.rb`.

## The problem

An update is carried out by the installed version's code. Downloading 0.5.0
and installing its Ruby, gems and migrations is all done by 0.4.x's
`UpdateOrchestrator`. So a fix to how updates work only helps the update
*after* the release that ships it. Every problem in the 0.5.0 update came from
this:

- mise's ready-made Ruby couldn't build gems on macOS 14, and the old updater
  couldn't be taught otherwise. The fix had to go into the Gemfile, the one
  file of the new release the old updater runs.
- A stalled `bundle install` hung forever with no output, and a restart of Roe
  killed the update partway through, because the update ran inside Roe's job
  process. The record stayed "in progress", which blocks every later update.

## The idea

The old updater does as little as possible: check, back up, download the new
release into `staging/`, then **hand off** to a script that ships in that
release, `staging/bin/update`. Everything after the download is the new
release's own code. Each release brings its own update steps, so a fix to how
updates work takes effect in the release that ships it.

0.5.1, the first release with the hand-off, is the last one whose updater code
matters for later updates. From then on the only code frozen in users'
installs is the hand-off (`Handoff`, the orchestrator's first three steps, the
Updates page's handling of `status.json`) and the contract below. Keep both
small, and support them forever.

The jump *into* 0.5.1 is still run by the previous release's in-process
updater; `bin/update` is simply carried along and used from the next update.

## What stays in the old updater (frozen once shipped)

`UpdateOrchestrator.start_update`, in this order:

1. **Validate**: git available, `staging/` empty.
2. **Back up the databases** (`BackupManager`, to
   `site/db/<env>/backup/<timestamp>/`), before anything else is touched. It
   stays here on purpose: a rollback is possible even if a release's script is
   broken. The timestamp is passed to the script as `--db-backup`.
3. **Download** into `staging/` (`Downloader`).
4. **Hand off** (`Handoff.start`) if `staging/bin/update` exists, and stop.
   Otherwise carry on with the in-process steps, so updating to a release
   without `bin/update` (a downgrade, an old nightly) still works. If the
   script can't be started, `staging/` is removed and the update is marked
   rolled back with nothing changed.

## How the script is started (`Handoff.launch`)

- **Copied first** to the update's own folder and run from there. `staging/`
  is renamed to `current/` partway through; the copy keeps a fixed path for
  resuming from a terminal.
- **Outside Roe**, through `/bin/sh -c 'bash … & echo $!'`, in its own process
  group, reading from `/dev/null`. The shell exits at once, so the script's
  parent is the system, not Roe's job process. That matters: the script stops
  and starts Roe's server and job processes, and on macOS `pgrep` never lists
  a process's own ancestors, so a script that was a child of the job process
  couldn't find it to stop it (found in rehearsal: the old job processes kept
  running from the deleted folder).
- **With a clean environment** (`Bundler.with_original_env`).
- **Bash** (decided): it runs before the new Ruby exists, and must work from a
  terminal when Roe won't start. Ruby is used only through commands run with
  the release's Ruby (`bin/rails db:migrate`, `assets:precompile`, a `ruby -e`
  for `VERSION`).

## The contract

This part can never change, only grow. Versioned by `--protocol`.

### Inputs

```
bash <update folder>/update.sh --protocol 1 --root <ROE_ROOT> \
  --update-id <id> --from <version> --to <version> --db-backup <timestamp>
```

Plus, from the Updates page: `--confirmed <key>` (the person confirmed the
question with that key) or `--cancel` (they cancelled it). For a person in a
terminal: `--resume` and `--rollback`, which need no other arguments; the
first run saves them in `args`.

The script must accept every protocol number an older Roe might pass. 0.5.1
passes `1`. A future Roe that needs more passes `2`, and scripts keep
supporting `1`. An unknown number: `state` `failed`, exit 2.

### The update folder

`<ROE_ROOT>/backups/updates/<YYYYMMDD_HHMMSS>-<update id>/`, made by the old
updater. The last 5 are kept (`Handoff::KEEP`). Not in `site/`, which Site
Sync carries to live; not in `current/`, which moves with the switch.

| File | Written by | What |
|---|---|---|
| `update.sh` | old updater | the copy of `staging/bin/update` that runs |
| `pid` | old updater, then script | the script's process ID (a terminal `--resume` writes its own) |
| `status.json` | script (old updater writes the first one) | the current state, replaced whole on every change |
| `log.txt` | script | everything, with times; command output streamed in |
| `journal` | script | one line per finished step, for resuming and rolling back |
| `args` | script | its arguments, for `--resume` / `--rollback` |
| `output.txt` | old updater | anything the script prints before it opens `log.txt` |

### `status.json`

```json
{
  "protocol": 1,
  "state": "running",
  "step": "Installing gems (84 so far)",
  "percent": 42,
  "message": null,
  "help": null,
  "question": null,
  "db_backup": "20261126_100230",
  "completed_at": null,
  "restarted": false,
  "cancelled": false,
  "updated_at": "2026-11-26T10:04:12Z"
}
```

- `state`: `running`, `waiting` (a question needs answering), `done`,
  `failed` (stopped and couldn't roll back), `rolled_back`.
- `message`: on `failed` / `rolled_back`, what went wrong, in plain words.
- `help`: steps for the person, Markdown, shown as written in any state.
- `question` (with `waiting`): `{ "key", "title", "text", "confirm",
  "cancel" }`. `text` is Markdown; `confirm` / `cancel` are the button labels.
  Any future step can ask anything without the page knowing in advance.
- `completed_at` (with `done`): when the update finished, set *before* the
  restart when the script restarted Roe. The page compares it with the
  server's start time to choose "Update Successful" or "Restart Roe".
- `cancelled` (with `rolled_back`): cancelled at a question. The page drops
  the record, as the old Ruby panel's CANCEL did.
- `updated_at`: changes only when the step text changes, so a stalled command
  shows as quiet.

Written through a temporary file and a rename, so the page never reads half
of it.

### What the Updates page does with it (`Handoff.sync`)

- **Mirrors it into the `UpdateStatus` record** on every page load and status
  poll: `state` to `status` (`running` → `in_progress`, `waiting` →
  `awaiting_input`, `done` → `completed`), `step`, `percent`, `message`, and
  the last 400 lines of `log.txt` to `log`. On `done` it does what the
  in-process updater did on completion: clears the update-available cache and
  prunes database backups.
- **Shows `question`** with its two buttons (`POST updates/answer`). Confirm
  starts the script again with `--confirmed <key>`; cancel with `--cancel`.
- **Shows `help`** with the progress, the rolled-back panel and the failed
  panel.
- **Stopped partway**: `running`, the process in `pid` gone, `updated_at`
  over 30 seconds old. The record becomes `failed`; the page shows "The update
  stopped partway", the log, and the `--resume` and `--rollback` commands.
- **Slow**: `running`, the process alive, `updated_at` over 10 minutes old.
  "This is taking longer than usual" above the log.
- **Restart**: polling carries on through failed requests while Roe restarts,
  and a redirect (to sign-in) reloads the page.

### Exit codes

`0` done or cancelled, `10` waiting for an answer, `2` bad arguments or
protocol, `3` already running, anything else failed. The page relies on
`status.json`; the codes are for people running it by hand.

## What 0.5.1's script does (free to change in any release)

Steps, each recorded in `journal` and skipped on `--resume`:

1. `ruby`: the Ruby in `.ruby-version` is installed (mise, or the Ruby on the
   PATH). If not, and `--confirmed install-ruby-<v>` wasn't given, write the
   question and exit 10. Then install it (mise; mise itself first if missing).
2. `gems`: `bundle install` in `staging/`, before anything changes, with a
   15-minute limit and three tries; the step shows a running count.
3. `test_migrations`: new migrations run on a copy of the site first, as the
   old `MigrationTester` did.
4. `migrate`: `bin/rails db:migrate` from `staging/` against the real site.
5. `switch`: `current/` → `current.backup/`, `staging/` → `current/`.
6. `secrets`, `root_files`, `docs`, `version`, `assets`: as the in-process
   steps did.
7. `restart`: if Roe is running, `roe.sh stop`, wait for a terminal's
   `roe.sh` to finish tidying up, `roe.sh start --daemon --no-browser` on the
   same port, then wait for `/up` to answer (200–499). A Roe started in a
   terminal window ends there and carries on in the background. If Roe wasn't
   running, it says to start it.
8. `done`; `current.backup/` is removed.

Any failure rolls back what `journal` says was done: switch back (stopping
and restarting Roe if needed), restore the databases from `--db-backup` if
migrations ran, restore the root files, remove `staging/`. Then
`rolled_back` with the reason and `help`, or `failed` if rolling back itself
went wrong. A new version that won't start is rolled back too, with the error
it printed (from `log/roe-daemon.log`) in `message`.

## Stuck in-process updates (`StuckUpdate`)

An in-process update (into 0.5.1, or to a release without `bin/update`) still
dies with Roe's job process. When its record is "in progress", has no update
folder, has been quiet for 20 minutes, the installed version is already its
`to_version`, and the server started after it went quiet, the Updates page
marks it finished. That clears records stuck like the one in the 0.5.0
report. Not yet built: finishing an interrupted hand-off from `roe.sh start`.

## Rehearsals (all passed before 0.5.1)

Scripts in the assistant's scratch folder: `rehearse-handoff-setup.sh` (a
fresh 0.5.1 install on port 3009 with its own mise and `ROE_HOME`, and a local
release repo), `rh-tag.sh` (tag a fake release; its `bin/update` logs
`REHEARSAL: running <version>'s own bin/update` and pauses in the gems step),
`rh-kill.sh`, `rh-state.sh`, and `rehearse-050-to-051.sh`.

1. 0.5.0 → 0.5.1 with 0.5.0's own in-process updater; 0.5.1 boots.
2. 0.5.1 → 0.5.2 through the Updates page: the log shows 0.5.2's own script
   ran; Roe restarted itself; the page reloaded to "Update Successful".
3. Roe restarted by hand mid-update: the update carried on and finished.
4. The script killed mid-update: "The update stopped partway" with the
   commands; `--resume` from a terminal finished it.
5. Gems that can't install: three tries, rolled back before the switch, Roe
   untouched.
6. A release that won't start: rolled back, databases restored, the old
   version started again, the error in the message (about 30 seconds).
7. The Ruby question: CANCEL dropped the attempt; INSTALL & CONTINUE
   installed Ruby 4.0.5 and its gems, and Roe restarted on it.
8. A release without `bin/update`: the in-process steps, ending with
   "Restart Roe".

## Decisions

1. **The script restarts Roe at the end.** No restart step for the person.
   Replaces the card "Update System: Auto-restart after update"
   (10462632993).
2. **Bash**, because it works when the old Ruby is what's broken, and from a
   terminal when Roe won't start.
3. **The database backup stays in the old updater**, first, as before.
4. **The update folder is `<ROE_ROOT>/backups/updates/`**, last 5 kept.

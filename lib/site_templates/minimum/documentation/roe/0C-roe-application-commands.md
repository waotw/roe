---
title: Roe App Commands
status: published
tags: guide
url_name: roe-application-commands
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Roe app commands

- `./roe.sh start` — Start Roe and, if you choose, open it in your browser at `http://localhost:3000`. Roe runs inside this Terminal window, so leave it open while you work. Quit with `control` + `c`.
- `./roe.sh stop` — Quit/stop Roe — run it from a second Terminal window while Roe is running.

You start and stop the Roe app with a small script called `roe.sh`, which lives in your Roe folder. These commands are run in your Terminal from within the Roe folder: [instructions](/documentation/roe/0-how-to-start-the-roe-app)

### How Roe and the Terminal work together

When Roe is running into the Terminal, you will see it do a bunch of stuff as you browse around your site and make changes. Once Roe is running, you don't run commands in that window or tab any longer. You would open a second window/tab and run Roe commands there.

For example, `./roe.sh help`. All Roe commands follow this pattern:

```
./roe.sh <command>
```

## Everyday commands

- `./roe.sh start` — Start Roe and, if you choose, open it in your browser at `http://localhost:3000`. Roe runs inside this Terminal window, so leave it open while you work. Quit with `control` + `c`.
- `./roe.sh stop` — Quit/stop Roe — run it from a second Terminal window while Roe is running.
- `./roe.sh restart` — Stop Roe and start it again. Useful when something looks off.
- `./roe.sh status` — Show whether Roe is running, along with which required tools are installed.

## Setup commands

- `./roe.sh check` — Check your computer for the tools Roe needs and offer to install anything missing. This is the first command you run on a new install.
- `./roe.sh setup` — Run the full setup: install Roe's libraries, create your `/site` folder, prepare the database, and create your admin account. Runs `check` first.
- `./roe.sh setup-mise` — Add the `mise activate` line to your shell's startup file, so the right version of Ruby is ready in new Terminal windows.

## Maintenance

- `./roe.sh update` — Check whether a newer version of Roe is available.
- `./roe.sh console` — Open a Rails console for inspecting your site directly. An advanced tool most people never need.

## See the list anytime

- `./roe.sh help` — Print this command list in the Terminal. `./roe.sh --help` and `./roe.sh -h` do the same.

## Need help?

If you run into a problem, have an idea for a new feature, or just want to say hello, we'd love to hear from you. Reach out with [issues](mailto:roe@weareontheweb.com?subject=Roe%20bugs), [feedback](mailto:roe@weareontheweb.com?subject=Roe%20feedback), [feature requests](mailto:roe@weareontheweb.com?subject=Roe%20requests), or a [hello](mailto:roe@weareontheweb.com?subject=Just%20saying%20hello).

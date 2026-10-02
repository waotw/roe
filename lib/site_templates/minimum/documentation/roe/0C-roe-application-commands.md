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

## Global Roe Commands

Type `roe` and hit `return` in any terminal window and you'll see a list of roe commands. Here is the pattern:

```bash
roe <command> <site-name>
```

- `list` -    Show every registered site and whether it's running
- `start` -   Start a site
- `stop` -    Stop a site
- `restart` - Stop, then start
- `status` -  Status for each Roe site
- `open` -    Open the site in your browser

This allows you to:

- manage one or more Roe sites from anywhere in the terminal
- run multiple Roe sites at once and switch between them
- start/stop all Roe sites with one command

If you only have one Roe site, you can use a shorthand and leave out the site name:

```bash
roe start
roe stop
roe open
roe restart
```

There is also an `--all` flag if you want to start, stop, restart all your Roe sites at once. Here is the pattern:

```
roe start --all
```

<mark>Note:</mark> If you see `command not found`, do the following:

- Open your Roe folder in the terminal: [instructions](/documentation/roe/0-how-to-start-the-roe-app#start-roe)
- Type this command: `./roe.sh register` and hit `return` to register this Roe site and install the global `roe` command.

## Application commands

The global `roe` command is using a small script inside your Roe folder called `roe.sh`. You can use this script directly to interact with Roe in more depth. This is primarily used by developers working on Roe.

To use `roe.sh`, you must open your Roe folder in the terminal. All Roe commands follow this pattern:

```
./roe.sh <command>
```

For example, type: `./roe.sh help` to get a full list of available commands.

### How `roe.sh` interacts with the terminal

When Roe is running in the Terminal, you will see it do a ton of stuff as you browse around your site and make changes. These are the logs and they show everything that's happening with the site.

When Roe is running in this way, you don't run any more commands in that window or tab. You would open a new window/tab to run commands.

### Everyday commands

- `./roe.sh start` — Start Roe and, if you choose, open it in your browser at `http://localhost:3000`. Roe runs inside this Terminal window, so leave it open while you work. Quit with `control` + `c`.
- `./roe.sh stop` — Quit/stop Roe — run it from a second Terminal window while Roe is running.
- `./roe.sh restart` — Stop Roe and start it again. Useful when something looks off.
- `./roe.sh status` — Show whether Roe is running, along with which required tools are installed.

### Setup commands

- `./roe.sh install` — Check your computer for the tools Roe needs and offer to install anything missing. This is the first command you run on a new install.
- `./roe.sh setup` — Run the full setup: install Roe's libraries, create your `/site` folder, prepare the database, and create your admin account. Runs `install` first.
- `./roe.sh setup-mise` — Add the `mise activate` line to your shell's startup file, so the right version of Ruby is ready in new Terminal windows.

### Maintenance

- `./roe.sh update` — Check whether a newer version of Roe is available.
- `./roe.sh console` — Open a Rails console for inspecting your site directly. An advanced tool most people won't need.

### See the list anytime

- `./roe.sh help` — Print this command list in the Terminal. `./roe.sh --help` and `./roe.sh -h` do the same.

## Need help?

If you run into a problem, have an idea for a new feature, or just want to say hello, we'd love to hear from you. Reach out with [issues](mailto:roe@weareontheweb.com?subject=Roe%20bugs), [feedback](mailto:roe@weareontheweb.com?subject=Roe%20feedback), [feature requests](mailto:roe@weareontheweb.com?subject=Roe%20requests), or a [hello](mailto:roe@weareontheweb.com?subject=Just%20saying%20hello).

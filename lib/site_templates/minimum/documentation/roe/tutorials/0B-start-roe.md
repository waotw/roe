---
title: 0) How to Start the Roe App
status: published
tags: tutorial
related:
  - 1-how-to-create-a-page
---

# How to Start and Quit the Roe App

Roe runs on your computer, so you need the app running to use it. Once you've installed and registered Roe, the easiest way to start and stop it is the global `roe` command — it works from **any** terminal window, so you don't have to find your Roe folder first.

If you finished the Roe installation, the app is already running. You can check any time:

1. Open any terminal window or tab
2. Type `roe list` and hit `return` — it shows every Roe site and whether it's running

## Start Roe

If you only have one Roe site, type `roe start` and hit `return`. Roe starts in the background, so you can close that terminal window and Roe keeps running.

- Your site opens at: [`http://localhost:3000`](http://localhost:3000)
- Roe's admin opens at: [`http://localhost:3000/admin`](http://localhost:3000/admin)

If you have more than one Roe site, run `roe list` to see their names, then start the one you want:

```
roe start <roe-site-name>
```

## Quit Roe

When you're finished for the day, type `roe stop` and hit `return`. If you have more than one site, Roe asks which one to stop.

## Restart Roe

If Roe ever behaves oddly, restarting usually sorts it out:

1. Open any terminal window or tab
2. Type `roe restart` and hit `return`

At any time you can type `roe` on its own and hit `return` to see the full list of commands.

## From the Roe folder instead

The global `roe` command is a convenience wrapper. You can always run Roe directly from its folder with `./roe.sh`, which is handy if you haven't registered the `roe` command yet (or you're working on Roe itself):

1. Open the Terminal and point it at your Roe folder.
    - Type `cd` and a space (don't press `return` yet), drag your Roe folder onto the Terminal window, then press `return`.
2. Type `./roe.sh start` and press `return`.
3. When Roe asks, press `y` to open it in your browser.
4. Unlike `roe start`, `./roe.sh start` runs **inside this Terminal window** — leave it open while you work, and quit with `control` + `c`.

See [Roe App Commands](/documentation/roe/roe-application-commands) for the full list of both `roe` and `./roe.sh` commands.

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

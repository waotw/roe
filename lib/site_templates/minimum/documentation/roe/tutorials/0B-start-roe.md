---
title: 0) How to Start the Roe App
status: published
tags: tutorial
related:
  - 1-how-to-create-a-page
---

# How to Start and Quit the Roe App

Roe runs on your computer, so you need to app running to use it. You start and quit it in the Terminal, from the Roe folder you downloaded.

If you finished the Roe installation, the app is already running in the terminal:

1. Open that terminal window
2. Hold down `control` and press `c`

This will quit Roe so you can start it again.

## Start Roe

1. Open the Terminal and point it at your Roe folder.
    - Type `cd` and a space (don't press `return` yet), drag your Roe folder onto the Terminal window, then press `return`.
2. Type `./roe.sh start` and press `return`.
3. Roe will ask you to `Choose` how you want to start:
    - press `y` to open Roe in your browser.
        - your site opens at: [`http://localhost:3000`](http://localhost:3000).
        - Roe's admin opens at: [`http://localhost:3000/admin`](http://localhost:3000/admin).
4. Leave this Terminal window open while you work — Roe runs inside it.

## Quit Roe

When you're finished for the day:

1. Click the Terminal window that's running Roe.
2. Hold `control` and press `c`.
    - Roe stops.

## Restart Roe

If Roe ever behaves oddly, restarting usually sorts it out: quit with `control` + `c`, then run `./roe.sh start` again.

`roe.sh` understands a handful of other commands too. See [Roe App Commands](/documentation/roe/roe-application-commands) for the full list.

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

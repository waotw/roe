---
title: 0) How to Start the Roe App
status: published
tags: tutorial
related:
  - 1-how-to-create-a-page
---

# How to `start` and `stop` the Roe App

Roe is an application that you start and stop from the terminal. If you finished the installation, you can simply type: `roe` in any terminal window or tab and you'll see a list of available commands.

The application may already running in the terminal, we can check:

1. Open any terminal window or tab
2. Type `roe list` and hit `return/enter`

This will show you all the Roe sites on your system and if they're running or stopped.

## Start Roe

If you only have one Roe site, simply type: `roe start` and hit `return/enter` to start up your site in Roe. This happens in the background. You can close that terminal window or tab, Roe will keep running.

If you have more than one Roe site, you can type `roe list` to see the name of the site. Then:

```
roe start roe-site-name
```

Hit `return/enter` and you'll start that specific site.

## Stop Roe

If you only have one Roe site:

1. Open any terminal window or tab
2. Type `roe stop` and hit `return/enter`

Roe will stop your site. If you have more than one, Roe will let you know and ask which site you want to stop.

## Restart Roe

If Roe ever behaves oddly, restarting usually sorts it out:

1. Open any terminal window or tab
2. Type `roe restart` and hit `return/enter`

Roe will restart your site. If you have more than one, Roe will let you know and ask which site you want to restart.

At any time you can type `roe` and hit `return/enter` to see the full list of global roe commands.

You can do more with Roe but you probably won't need to at the moment. See [Roe App Commands](/documentation/roe/roe-application-commands) for more information.

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

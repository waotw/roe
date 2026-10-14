---
title: "Troubleshooting → Site Sync"
status: published
url_name: ts-site-sync
tags: troubleshoot
related:
  - troubleshoot-deploy
  - site-sync
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Troubleshooting Site Sync

## General

### "Last contact" shows an error

- Check that your Live Site URL is correct
- Make sure the live site is running
- Verify both sites use the same sync token

### Push/Pull buttons are disabled

- Wait for sync status to refresh
- Check that the connection is healthy
- Verify you typed `LIVE` correctly when confirming

### "The live site can't send large files yet" or "can't receive large files yet"

Files over 25 MB, such as videos, travel between your sites in pieces. Your live site is running an older version of Roe that can't do this yet.

[Deploy](/documentation/guide-deploy) the version of Roe you have locally to your live site, then sync again. Nothing is lost in the meantime: the sync stops before changing anything.

### "Files differ from Live site, though neither side's sync record shows a change"

Both sites keep a record of the files they last agreed on. This message means some files are different on each site, but neither record shows them changing. Usually a file was edited while a long sync was running.

The message lists the files. Click `SYNC WITH LIVE`. If syncing a file would replace a newer copy with an older one, Site Sync stops and asks which version to keep instead of choosing for you.

## Kamal

### `Permission denied (publickey)`

This is an SSH key error. The most common Site Sync failure. The host/server rejected the SSH key your machine offered. Two things both need to be true for Site Sync to work via SSH:

**1. The right key is picked in Roe.**

Go to [Deploy settings](/admin/configs/deploy/edit) → **Common Settings** → **SSH key** dropdown. Pick the key whose public counterpart is authorized on the server. Save.

**2. The counterpart SSH key has been added to your host/server**

The best instructions for setting up SSH on your host/server is in your host's documentation. Search there first.

If you're unfamiliar with SSH, read this article: [How To Set up SSH Keys on a Linux / Unix System](https://www.cyberciti.biz/faq/how-to-set-up-ssh-keys-on-linux-unix/)

This article explains [How to Create SSH Keys with OpenSSH on macOS or Linux](https://docs.digitalocean.com/products/droplets/how-to/add-ssh-keys/create-with-openssh/)

This article explains [How to Manage SSH Public Keys on DigitalOcean](https://docs.digitalocean.com/platform/teams/how-to/upload-ssh-keys/), which is very similar to other platforms.

## Fly

### `Error: Not authenticated` / Site Sync fails when Fly is your host/server

From your Roe install directory:

```bash
fly auth login
```

That opens a browser window to authenticate. Session persists locally afterward.

### `Fly CLI not installed`

**macOS (Homebrew):**

```bash
brew install flyctl
```

**macOS / Linux (official installer):**

```bash
curl -L https://fly.io/install.sh | sh
```

Then sign in:

```bash
fly auth login
```

### `App not found`

The app name in [Deploy settings](/admin/configs/deploy/edit) doesn't match an app in your Fly account. Verify:

```bash
fly apps list
```

The app name in this list must match **App name** in Deploy settings exactly. Lowercase, no spaces, hyphens only.

## General

### Restart helps

A fresh restart re-reads all settings.

### Still stuck?

Run Site Sync, copy the full error from the failed-transfer panel, and send an email: [roe@weareontheweb.com](mailto:roe@weareontheweb.com)

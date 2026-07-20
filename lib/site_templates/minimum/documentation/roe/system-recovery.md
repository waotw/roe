---
title: "Recovery"
status: published
tags: system
related:
  - site-sync
  - guide-deploy
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Recovery: it's probably note a disaster

Roe is built so your work is hard to lose. Everything you write lives as ordinary files, and when you have a live and loca site, Roe keeps more than one copy in more than one place. So if a laptop dies, a page gets deleted, or a sync goes sideways, getting back to normal is usually a few clicks — not a crisis.

This guide shows you where your work is kept and, _should you ever need it_, how to bring your site back.

## Where your work is kept

Roe keeps your site safe in layers, so a single mishap is never the whole story:

- **Your content is plain files.** Everything you write is Markdown, and your media sits beside it, in the `/site` folder. You can open, copy, and back these up like any other files — no database needed to read them.
- **A copy on your live site.** Every time you [Sync with Live](/documentation/roe/site-sync), your content is mirrored between your computer and your live server — a second copy, in a second place, kept current as you work and sync.
- **Local backups.** Roe keeps browsable snapshots of your whole `/site` folder. Each one is a complete copy you can restore from.
- **Live-database backups.** Each sync also captures an encrypted backup of your live site's database, so things like member accounts and saved settings are protected too.

## A little preparation

You don't need to do much, but two habits make recovery simple:

1. **Set a backup passphrase.** On your live site, open **Admin → Site Sync** and set a backup passphrase. This is what locks — and later unlocks — your encrypted database backups. Keep it somewhere safe; a password manager is ideal.
2. **Sync now and then.** Each [Sync with Live](/documentation/roe/site-sync) refreshes the copy on your server and captures a fresh database backup. Syncing regularly keeps your safety net current. Roe will let you know with a small orange dot when there are changes that have not been synced.

With those in place, the sections below are simply here if you ever need them.

## Restore something you deleted or changed

1. Open your Roe folder in your computer
2. Find your `backups/` folder
3. Open it and look for the most recent version you have backuped up
4. Move the file to the same folder under `site/`

### You can also restore and entire local backup:

1. Open **Admin → Site Sync** and choose the **Backups** tab.
2. Under **Local Backups**, find the snapshot from before the change.
3. Click **Restore** next to it.
   Roe snapshots your current `/site` first, as a safety net, then restores the older copy.

If your live site still has the good version, you can also just **Sync with Live** to pull it back.

## Rebuild on a new computer

Lost the machine Roe was on? Your live site still has everything since your last sync. To set up again:

1. [Install Roe](/documentation/roe/guide-installation) on the new computer.
2. **Reconnect to your live site.** Open **Admin → Site Sync** and set up the connection: enter your live site's address, then make the sync token match on both ends. Your fresh install already has its own token — copy it into your live site's Site Sync settings so both sides share the same one. See [Site Sync → Setup](/documentation/roe/site-sync#setup) for the walkthrough.
3. **Sync with Live** to pull your content back down.

Your writing and media come home from the live copy, and you're back where you left off.

## Restore your live database

If your live site's database is ever damaged or lost — important data (members, payments, newsletter history) lives there — restore it from one of the encrypted backups:

1. On your **local** Roe, open **Admin → Site Sync → Backups** and choose the **Public/Live Site Backups** tab.
2. Find the backup you want and click **Download .enc**.
3. Open **Site Sync** on your **live** site, click **RESTORE DATABASE…**, and upload the file you downloaded.

Once your live site restarts, Roe checks that the restored keys can read the data — and if anything doesn't line up, it quietly puts the previous database back. A restore can't leave your site worse off than before.

Want to look inside a backup without touching anything live? Use **Decrypt & download** for a plain, readable copy on your computer. It never connects to any live database.

## Keep your passphrase safe

Your encrypted database backups can only be opened with your backup passphrase. Roe never stores it for you — which is exactly what keeps those backups private. Save it somewhere you won't lose it, like a password manager, and you'll always be able to open a backup when you need one.

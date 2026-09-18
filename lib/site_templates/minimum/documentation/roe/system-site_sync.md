---
title: Site Sync
status: published
tags: system
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

**This article covers:** [Site Sync](#when-to-use-site-sync), [Static Site Sync](#static-site-sync) and [Site Backups](#site-backups).

# Site Sync

In Roe, there is a "local site" and a "live site". The local site is the `site/` folder on your laptop or desktop computer. The "live site" is the `site/` folder on a web host or public server.

Site Sync "syncs" these folders so that what is local and what is live is the same.

Site Sync:

- tracks changes on the "local site" and "live site"
- `syncs` changes between them.
- only sends the files that have changed, not the entire site folder (except for the first sync)

<mark>Note:</mark> Site Sync handles content only. If you've updated Roe to a new version, you want to [Deploy](/documentation/guide-deploy).

**Typical workflow:**

1. Write and edit content locally
2. **Site Sync** → Push content to live
3. (Weeks later) Roe releases an update
4. Update your local version of Roe
4. **Deploy** → Send update to live site
5. Make some edits to a post on the live site
5. **Site Sync** → Pull those changes to your local site

## When to Use Site Sync

| Scenario | Action |
|----------|--------|
| First sync | Syncs entire local `site/` folder to your live site |
| Published new posts on your local site | Syncs new posts to your live site |
| Edited content on the live site | Sync changes to your local site |
| Setting up a new computer | Sync your live site to your new computer |
| Regular backup | Create local backup |

### Setup

#### First Time

1. Deploy your Roe app to your host (see [Guide → Deploy](/documentation/guide-deploy))
2. Go to [Admin → Site Sync](/admin/site_sync) on your **local** site
3. Enter your **Live Site URL** (e.g., `https://yoursite.com`)
4. Click **Save Settings**
5. Click **Refresh Sync Status**
6. You should see "Last contact with Live site: less than a minute ago"

#### Authentication

Site Sync uses a token to authenticate between your local and live sites. Both sites must share the same token.

The token is generated automatically. If you need to set it manually (for example, when restoring from backup):

1. Copy the token from your local Site Sync settings
2. On the live server, sign into the Admin and paste the token in the "Paste local token here" field and click `SAVE TOKEN`.

### How to use Site Sync

Site Sync both pulls changes from your live site and pushes changes from your local site.

1. Make sure sync status shows a successful connection (Roe will tell you if there's no connection)
2. Click `SYNC WITH LIVE`
3. Wait for the sync to complete

The first push may take several minutes depending on how much media you have. Subsequent pushes are faster because only changed files are transferred.

### How Site Sync handles conflicts

You might have edited the same post or page on the live site and the local site. If this happens, you will be asked to confirm which file should be kept. By default, Roe will prioritize the file that was modified more recently.

### Sync Status

The Site Sync page shows:

- **Last contact** — When the live site was last reached
- **Local changes** — Files modified locally since last sync
- **Live changes** — Files modified on live since last sync
- **SYNC WITH LIVE button** — Available when connection is healthy

### Sync history

There is a `View sync history →` link on the [Site Sync](/admin/site_sync) page. This shows you a running log of every change a sync makes from live → local and from local → live. For changes from your local site (Live → Local), you can select files and click RESTORE SELECTED to bring them back from the backup taken just before that sync — whether the file was overwritten or deleted. Changes pushed to live are listed but can't be reversed from here yet; working on this for the next release.

- select the file you want to restore
- click `RESTORE SELECTED`

### Deleted files warning

Site sync deletes files. If a file is deleted on your live site, sync will delete locally and vice-versa. To prevent accidentally deleting files, Roe has a warning in place which allows you to confirm all deletions. You can set a threshold for this in Settings → [site.yml](/admin/configs/site/edit) in the `Site Sync` section or turn it off entirely with `never`.

### Best Practices

- **Work locally, sync to live** — Do your writing and editing locally, then push
- **Sync before deploying** — Make sure your content is synced before updating or deploying Roe
- **Pull before major edits** — If you edit on live, sync to local often to keep things in sync
- **Use Sync history to restore files** — If you sync and want to rollback a file, you can use the [Sync history](/admin/site_sync/history) page to restore a file to a backup made just before files are synced.

## Static Site Sync

Roe can build a [static site](/documentation/glossary#ssg) which you can upload to almost any webhost. You can enable static site generation [Admin → Settings → site.yml](/admin/configs/site/edit) page.

<mark>Note:</mark> This section will only be present if Static Site Sync is enabled.

### Sync Status

This shows the last time you've pushed a website to a static host or downloaded your zip file. 

### Download Zip

Many static site web hosts can take just a zip or folder:

1. `DOWNLOAD ZIP`
2. Sign into webhost and find the File Manager
3. Upload Zip or Folder (whichever is needed)
4. The site is live

### SFTP & FTPS

These are common protocols for transferring files over the internet. A webhost will have documentation about the right protocol to use. Set up the settings that work with your host.

#### Push

Once settings are in place, `TEST CONNECTION` and once green, `PUSH`. This will send your local `static_site/` folder to a host folder. It will only send files that have changed since your last `PUSH`.

## Site Backups

Site Sync does 3 things when you sync:

1. A full local backup
2. A partial live backup
3. A full backup of the live database (encrypted)

### Full local backup

Site Sync creates an entire backup of your local site when you sync. It also will backup before you restore a file in Sync History or restore from a previous backup.

The backup system is smart:

- first time, full backup of everything
- subsequent backups only track what changed since the previous backup
- this keeps the size of each backup to a much more reasonable size

### Partial live backup

Site Sync creates a backup of any content that was changed on the live site and has been updated or modified by the sync. This allows you to restore or reverse changes made to the live site, such as an accidental deletion. Roe keeps up to 15 live backups.

### Full encrypted backup of live database

Site Sync can create a full backup of your live database. This includes all your members, payment and delivery history. Roe keeps up to 15 local backups in the `backups` folder (created when the first backup is created). In order to use this feature, you'll need to:

1. Go to your live site and sign into the Admin
2. Go to the Site Sync page and click `Site Backups`.
3. Add a passphrase for your backup. Save this in a safe place. It's the only way to decrypt the backup and read what's in it.
4. Open your local site and go to Site Sync → Site Backups. You should see "Database backup encryption: ON". <mark>Note: do a Site Sync to refresh the status if needed.</mark>

Now, each time you use Site Sync, it will download an encrypted backup of your live database.

### Restoring from a Local Backup

You can restore any of these and it will make your site reflect whatever is in that backup. Doing this will trigger a new backup right before the restore so you can reverse any restoration.

1. Go to Site Sync → Site Backups → Local
  - You'll see a list of local backups
2. Click `RESTORE` on any backup

If you regret this decision, refresh the page and you can restore to the backup that was just made before you clicked `RESTORE`.

### Restoring from a Live Backup

This should not be required often and is protection against catastrophic data loss. Only do this if absolutely necessary.

1. Go to Site Sync → Site Backups → Live Site
2. Click `DOWNLOAD .ENC`
  - This will pull an encrypted backup into your downloads folder.
3. Visit Site Sync on your live site and click `RESTORE DATABASE`.
4. Then upload the file you just downloaded.
5. Restart the live site (`kamal app boot` / `fly deploy` as shown on the page)

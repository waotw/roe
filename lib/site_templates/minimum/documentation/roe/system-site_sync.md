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

**This article covers:** [Site Sync](#when-to-use-site-sync), [Static Site Sync](#static-site-sync) and Site Backups.

# Site Sync

In Roe, there is a "local site", this is the `site/` folder on a laptop/personal computer, and a "live site", this is the `site/` folder on a webhost/server.

Site Sync:

- tracks changes on the "local site" and "live site"
- `syncs` changes between them.
- only sends the files that have changed, not the entire site folder.

<mark>Note:</mark> Site Sync handles content only. If you've updated Roe to a new version, you want to [Deploy](/documentation/guide-deploy).

**Typical workflow:**

1. Write and edit content locally
2. **Site Sync** → Push content to live
3. (Weeks later) Roe releases an update
4. Update your local version of roe
4. **Deploy** → Send update to live site
5. **Site Sync** → Push new content to live

## When to Use Site Sync

| Scenario | Action |
|----------|--------|
| First deploy | Push local content to live site |
| Published new posts locally | Push to live |
| Edited content on live server | Pull to local |
| Setting up a new computer | Pull from live |
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
2. On the live server, sign into the Admin and paste the token on the same 

### Push to Live

Send your local content to the live site:

1. Make sure sync status shows a successful connection
2. Click **Push to Live**
3. Type `LIVE` to confirm
4. Wait for the sync to complete

The first push may take several minutes depending on how much media you have. Subsequent pushes are faster because only changed files are transferred.

### Pull from Live

Download content from the live site to your local machine:

1. Click **Pull from Live**
2. Type `LIVE` to confirm
3. Wait for the sync to complete

Use this when:

- You've made changes directly on the live server
- You're setting up Roe on a new computer
- You want to create a local backup

### Sync Status

The Site Sync page shows:

- **Last contact** — When the live site was last reached
- **Local changes** — Files modified locally since last sync
- **Live changes** — Files modified on live since last sync
- **Push/Pull buttons** — Available when connection is healthy

### Best Practices

- **Work locally, sync to live** — Do your writing and editing locally, then push
- **Sync before deploying** — Make sure your content is synced before updating Roe
- **Pull before major edits** — If you edit on live, pull to local first to avoid conflicts
- **The live database is separate** — Your local and live databases are independent. Site Sync handles the database content as part of the sync process.

## Static Site Sync

Roe can build a [static site](/documentation/glossary#ssg) which you can upload to almost any webhost. You can enable static site generation [Admin → Settings → site.yml](/admin/configs/site/edit) page. <mark>Note:</mark> This section will only be present if Static Site Sync is enabled.

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

Once settings are in place, `TEXT CONNECTION` and once green, `PUSH`. This will send your local `static_site/` folder to a host folder. It will only send files that have changed since your last `PUSH`.

## Site Backups

Site Sync creates a backup of the local site and the live site every time there is a `PUSH TO LIVE NOW` or a `PULL FROM LIVE`. Local content snapshots are stored in `backups/local/`; an encrypted backup of the live database is captured each sync under `backups/live/database/` (see the **Live Site** tab). Pre-push safety snapshots of live content are kept internally under `backups/live/content/`.

The backup system is smart:

- first time, full backup of everything
- subsequent backups only track what changed since the previous backup
- this keeps the size of each backup to a much more reasonable size

Scroll down the Site Backups section to trigger a local backup manually with `CREATE BACKUP`

### Restore from a Backup

If something goes wrong, you will have backups available and your can `RESTORE` any of them. The last 15 backups are kept.

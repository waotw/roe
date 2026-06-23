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

# Site Sync

Site Sync keeps your local Roe site in sync with your live production site. It uses a secure API connection to push or pull content between your local machine and your deployed server.

## What Site Sync Does

Site Sync handles your `/site` folder — everything that isn't the Roe application itself:

- Posts, pages, products, and documentation
- Media (images, audio, video)
- Themes and custom CSS
- Configuration files
- Database content

<mark>Note:</mark> Site Sync handles content. For code updates to Roe itself, use [Deploy](/documentation/deployment).

## When to Use Site Sync

| Scenario | Action |
|----------|--------|
| First deploy | Push local content to live site |
| Published new posts locally | Push to live |
| Edited content on live server | Pull to local |
| Setting up a new computer | Pull from live |
| Regular backup | Pull to create local backup |

## Setup

### First Time

1. Deploy your Roe app to your host (see [Deployment](/documentation/deployment))
2. Go to [Admin → Site Sync](/admin/site_sync) on your **local** site
3. Enter your **Live Site URL** (e.g., `https://yoursite.com`)
4. Click **Save Settings**
5. Click **Refresh Sync Status**
6. You should see "Last contact with Live site: less than a minute ago"

### Authentication

Site Sync uses a token to authenticate between your local and live sites. Both sites must share the same token.

The token is generated automatically. If you need to set it manually (for example, when restoring from backup):

1. Copy the token from your local Site Sync settings
2. On the live server, open a Rails console and set the same token

## Push to Live

Send your local content to the live site:

1. Make sure sync status shows a successful connection
2. Click **Push to Live**
3. Type `LIVE` to confirm
4. Wait for the sync to complete

The first push may take several minutes depending on how much media you have. Subsequent pushes are faster because only changed files are transferred.

## Pull from Live

Download content from the live site to your local machine:

1. Click **Pull from Live**
2. Type `LIVE` to confirm
3. Wait for the sync to complete

Use this when:
- You've made changes directly on the live server
- You're setting up Roe on a new computer
- You want to create a local backup

## Sync Status

The Site Sync page shows:

- **Last contact** — When the live site was last reached
- **Local changes** — Files modified locally since last sync
- **Live changes** — Files modified on live since last sync
- **Push/Pull buttons** — Available when connection is healthy

## Site Sync vs Deploy

| | Site Sync | Deploy |
|---|---|---|
| **What** | Content (`/site` folder) | Roe application code |
| **When** | After writing/editing content | After Roe updates or code changes |
| **How often** | Multiple times per day | Rarely (when updating Roe) |
| **Speed** | Fast (incremental) | Slow (full build) |

Typical workflow:

1. Write and edit content locally
2. **Site Sync** → Push content to live
3. (Weeks later) Roe releases an update
4. **Deploy** → Update the Roe application
5. **Site Sync** → Push any new content

## Troubleshooting

### "Last contact" shows an error

- Check that your Live Site URL is correct
- Make sure the live site is running
- Verify both sites use the same sync token

### Push/Pull buttons are disabled

- Wait for sync status to refresh
- Check that the connection is healthy
- Verify you typed `LIVE` correctly when confirming

### Conflicts

If the same file is edited on both local and live, the most recent version wins. There is no merge interface — review your content after syncing if you suspect conflicts.

## Best Practices

- **Work locally, sync to live** — Do your writing and editing locally, then push
- **Sync before deploying** — Make sure your content is synced before updating Roe
- **Pull before major edits** — If you edit on live, pull to local first to avoid conflicts
- **The live database is separate** — Your local and live databases are independent. Site Sync handles the database content as part of the sync process.

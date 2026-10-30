---
title: Updates & Deploy
status: published
tags: admin
---

# Updates & Deployment

Roe makes updates and deployment almost one-click. If you run into trouble, read on…

<mark>Note:</mark> If you've edited anything in Roe's code base (`/current` folder), don't use the Update System. This will override any local changes to the code base. This does not apply to your `/site` folder. Edits there are not affected by the Update System. 

## Updates

Updates in Roe are handled delicately. The system:

1. makes a full backup of your site before anything else happens
2. makes a copy of your database to test any changes there before moving forward
3. if anything fails, it rollback automatically, your site is exactly as it was
4. if database changes work, it runs those changes on your database
5. it finishes by removing the old code and replacing it with the new code

Updates are handled on this page: [Admin → Updates & Deploy](/admin/updates). When there is an update available, you should see an amber dot above the link in Admin. However, you can manually check for updates as well:

- Click the `CHECK FOR UPDATES` button to manually check for updates.
- If an update is available, you'll see an `Update Now` button
- You'll see a running log of what is happening…
- When it finishes, Roe asks you to restart. Open any terminal window, type `roe restart` and press `return/enter` — if you have more than one Roe site, the page shows the exact command with your site's name. Then refresh the page.
    - If `roe` isn't set up, or something goes wrong during the update, open your Roe folder in the terminal and restart there instead: `ctrl-c` to stop it and `./roe.sh start` to start it again.

## Deployment

Deployment is similar. There is a full guide to deployment here: [Guide → Deploy]

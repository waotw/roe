---
title: "Settings → Deployment"
status: published
url_name: settings-deployment
tags: settings
related:
  - guide-deploy
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Global Deploy Settings

## Configure Roe for Fly

In your local Roe admin: [Settings → deploy.yml](/admin/configs/deploy/edit)

1. **Target**: select **Fly.io**.
2. **App name**: paste the name you just created (e.g. `site-name-roe`).
3. **Region**: choose a region close to you or your audience. `iad` (US East), `lhr` (London), `syd` (Sydney) are common choices. Run `fly platform regions` in your terminal for the full list.
4. **VM memory**: `1gb` is right for most sites. If your site has hundreds-thousands of posts, consider bumping to `2gb`.
5. **Volume size (GB)**: how much disk to allocate for your `/site` folder, databases, and logs. Roe shows your current `/site` size and a suggested target — use the suggested value as a starting point.

Click **Save**. Roe writes `fly.toml` (Fly's config file) with your settings.

## Configure Roe for Kamal

Roe needs three values to deploy. You set them once in the Roe admin UI; Roe writes the necessary config and secrets files for you.

Go to: [Admin → Settings → deploy.yml](/admin/configs/deploy/edit).

Fill in the three required fields:

1. **Droplet IP address** — the public IP from your DigitalOcean droplet.
    - If you've already set up a custom domain, you can use that instead, e.g. `your-site.com`
2. **Docker Hub username** — the username from your Docker Hub account.
3. **Docker Hub access token** — the personal access token you generated earlier. (This one is treated as a secret — it's stored encrypted and never displayed after save.)

Click **Save**. Roe generates two files behind the scenes:

- `/current/config/deploy.yml` — Kamal's main configuration
- `/current/.kamal/secrets` — holds your Docker Hub access token

<mark>Note: Both files are written to the right place and given the right permissions. You don't need to open or edit either one directly.</mark>

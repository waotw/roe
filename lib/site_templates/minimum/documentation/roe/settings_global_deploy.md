---
title: "Settings → Global → Deployment"
status: published
url_name: deployment
---

##### Related documentation

```collection
source: documentation
related: true
template: links
```

# Deploy the Roe app to your host

Roe splits up your site into 2 parts:

1. The app: `/current` which holds the Rails app that runs Roe and builds your site.
2. The `/site` which holds all pages, posts, content, media, themes, databases, etc.

- `Deploy`: pushes and installs the Roe app to a web host
- `Site Sync`: pushes/syncs your site content with your web host

Roe CMS supports two deployment options: **[Fly.io](https://fly.io)** (recommended for hands-off deloyment, a little pricier) and **[Kamal](https://kamal-deploy.org/)** which works on any host that supports VPS like DigitalOcean (recommended for bring-your-own-host, not too much more work).

Both routes use Docker images under the hood, but Fly removes most of the server-side setup work — no SSH keys, no Docker Hub account, no provisioning. If you're not sure which to pick, start with Fly.

This document covers Fly.io first, then Kamal + DigitalOcean (for a specific host walk-through)

### For any deploy target:

- Good idea to add your **site URL** set in [Settings → site.yml](/admin/configs/site/edit) (e.g. `https://yoursite.com`).

## Fly.io

Fly is the most hands-off path to a live Roe site. You install the CLI tool (`flyctl`), sign in, click Deploy from Roe's admin, and Fly handles the rest — image builds, container hosting, persistent storage, SSL, and routing. Great user experience - can cost a bit more than other [VPS](https://medium.com/@fimber6/vps-explained-what-it-is-how-it-works-and-why-you-might-need-one-061606936a78)s.

### Create a Fly Account

1. Go to [fly.io](https://fly.io) and sign up.
2. Add a payment method. Fly offers free credit for new accounts; small Roe sites typically run for under $10 per month.

### Install flyctl

`flyctl` is Fly's command-line tool. This is used by Roe to `DEPLOY` the app.

**Mac (Homebrew):**

```bash
brew install flyctl
```

**Mac / Linux (official installer):**

```bash
curl -L https://fly.io/install.sh | sh
```

**Windows (PowerShell):**

```powershell
iwr https://fly.io/install.ps1 -useb | iex
```

Verify it's installed:

```bash
fly version
```

### Authenticate

Sign in to Fly from your terminal — this gives `flyctl` an API token to your account so Roe's deploy job can build and deploy images on your behalf:

```bash
fly auth login
```

This opens a browser window for you to confirm. After login, `flyctl` stores the token under `~/.fly/`.

### Create Your App

You only do this once. Pick a globally-unique name for your app — this becomes part of your `.fly.dev` URL until you point a custom domain at it.

Navigate to: `path/to/roe/current`.

```bash
fly apps create site-name-roe
```

If the name is taken, Fly will tell you and you can try another.

### Configure Roe for Fly

In your local Roe admin: [Settings → Global → deploy.yml](/admin/configs/deploy/edit)

1. **Target**: select **Fly.io**.
2. **App name**: paste the name you just created (e.g. `site-name-roe`).
3. **Region**: choose a region close to you or your audience. `iad` (US East), `lhr` (London), `syd` (Sydney) are common choices. Run `fly platform regions` in your terminal for the full list.
4. **VM memory**: `1gb` is right for most sites. If your site has hundreds-thousands of posts, consider bumping to `2gb`.
5. **Volume size (GB)**: how much disk to allocate for your `/site` folder, databases, and logs. Roe shows your current `/site` size and a suggested target — use the suggested value as a starting point.

Click **Save**. Roe writes `fly.toml` (Fly's config file) with your settings.

### Deploy

In [Admin → Updates & Deploy](/admin/updates), click `DEPLOY`. Roe runs `fly deploy` behind the scenes:

1. Builds a Docker image from your current Roe install.
2. Pushes it to Fly's registry.
3. Provisions the volume for your `/site` and database storage if it doesn't exist yet.
4. Starts a container running Roe.
5. Sets `RAILS_MASTER_KEY` and your admin credentials as Fly secrets, so the live container can decrypt config and let you log in immediately.

Expect 5–10 minutes for the first deploy. Subsequent deploys are faster (2–4 minutes) because Fly caches Docker layers.

The deploy log streams live in the admin panel — you'll see each step as it runs.

### Verify the Deploy

1. Once the deploy completes, your site is live at:
    ```
    https://site-name-roe.fly.dev
    ```
2. Visit it in a browser. If you've started to add content to your local Roe site, sync it to Fly with Site Sync (covered next). If not, you'll see Roe's empty-site placeholder.
3. Sign in to the live admin at `https://site-name-roe.fly.dev/admin` using **the same email and password you use locally**.

### Site Sync (push site content to Fly)

The first deploy ships the Rails app but not your `/site` folder (your content). Send your local content to the live site via Site Sync:

1. On your local admin, go to [Admin → Site Sync](/admin/site_sync).
2. The Live Site URL field will be pre-filled with your `https://site-name-roe.fly.dev` address. If not, paste it in and click `SAVE SETTINGS`.
3. Come back to Roe and click `REFRESH SYNC STATUS` at the top. You should see "Last contact with Live site: less than a minute ago" — that confirms the API connection works.
4. Type `LIVE` to confirm and click `PUSH TO LIVE`.

The first time you do this, it might take a little bit but future syncs will be much faster as there will be less to sync. The page will auto-refresh as your site syncs and let you know when it's finished. Reload your live site to see everything.

### Custom Domain and SSL

Fly issues a `https://<your-app-name>.fly.dev` URL automatically with SSL — you can launch with that. When you have a custom domain, follow along with Fly's documentation to set it up: [Custom domains](https://fly.io/docs/networking/custom-domain/)

Remember to update the Site URL here: [Admin → Settings → site.yml](/admin/configs/site/edit) if you haven't already.

### Going Forward: Routine Deploys

After the first deploy, everything's set up. Routine deploys are one click:

1. Go to: [Admin → Updates & Deploy](/admin/updates) and click `DEPLOY`.
    - If there have been any code changes, click `AUTO-COMMIT & DEPLOY` or commit yourself and click `REFRESH`, then `DEPLOY`
2. Wait for the streaming log to show "Deploy completed successfully".
3. Reload your live site.

---

## Kamal (Standard Rails Deployment) + DigitalOcean

### Set Up a Docker Registry

Kamal builds the Roe image locally and pushes it to a [Docker registry](https://www.youtube.com/watch?v=2WDl10Wv5rs). Your host pulls from this registry to deploy the app. **Docker Hub** is the easiest option for getting started.

#### Create a Docker Hub Account

1. Go to [hub.docker.com](https://hub.docker.com) and sign up.
2. Verify your email.

#### Generate a Personal Access Token

Don't use your account password — generate a dedicated token instead:

1. Docker Hub → **Account Settings → Personal Access Tokens → Generate New Token**
2. Description: `roe-kamal-deploy`
3. Expiration: `None` (or pick the longest option offered)
4. Permissions: **Read, Write, Delete** (Kamal needs all three)
5. Copy the token immediately — Docker Hub only shows it once
6. Paste this into Roe: [Settings → deploy.yml → Registry token](/admin/configs/deploy/edit)

### Configure Roe for Kamal

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

### Install the Docker Desktop App

By default, Roe builds your Docker image on your computer. To do this, you need Docker running. If you don't have it set up, download the [Docker Desktop app](https://www.docker.com/products/docker-desktop/) and launch the app. Docker will be running after that.

### Deploy

#### First Deploy

The first time you deploy, use `kamal setup`. This:

1. Installs Docker on the droplet (if not present)
2. Logs into Docker Hub from the droplet
3. Builds the Roe image
4. Pushes it to Docker Hub
5. Pulls it on the droplet and starts the container

##### In your terminal: Open the Roe app/current folder
```bash
cd /path/to/your/roe/current
```

##### In your terminal: run `kamal setup`
```bash
kamal setup
```

Expect 5–10 minutes on first run. Subsequent deploys will be one click on your [Updates & Deploy](/admin/updates) page. Just click `DEPLOY`.

In the future, if there are any changes to Roe's code, you'll be prompted to commit the changes before deploy:

- Click `AUTO COMMIT & DEPLOY` or commit the changes yourself and click `REFRESH`. Then `DEPLOY`.

#### Verify the Deploy

Once `kamal setup` finishes, hit your droplet's IP in a browser:

```
http://<your-droplet-ip>
```

#### Sign In on the Droplet

Sign in at `http://<your-droplet-ip>/admin` using the same email and password you use locally.

## Site Sync (push site content to your live site)

The first deploy ships the Rails app but not your `/site` folder (your content). Send your local content to the live site via Site Sync:

1. On your local admin, go to [Admin → Site Sync](/admin/site_sync).
2. The Live Site URL field will be pre-filled with your Site URL. If you haven't setup a custom domain for DigitalOcean yet, use `<your-droplet-ip>` address for now and paste it here.
3. Come back to Roe and click `REFRESH SYNC STATUS` at the top. You should see "Last contact with Live site: less than a minute ago" — that confirms the API connection works.
4. Type `LIVE` to confirm and click `PUSH TO LIVE`.

The first time you do this, it might take a little bit but future syncs will be much faster as there will be less to sync. The page will auto-refresh as your site syncs and let you know when it's finished. Reload your live site to see everything.

### Custom Domain and SSL (when ready)

For your first deploy you can run on the droplet's IP over plain HTTP. When you have a domain ready: follow these DigitalOcean's (or your host's) instructions for setting up a custom domain: [How to add Custom Domains](https://docs.digitalocean.com/products/networking/dns/how-to/add-domains/)

Once you have your custom domain pointed at your Droplet, you should add this to your Kamal → Custom domain at [Settings → deploy.yml](/admin/configs/deploy/edit)

### Going Forward: Routine Deploys

After the first deploy, everything's set up. Routine deploys are one click:

1. Go to: [Admin → Updates & Deploy](/admin/updates) and click `DEPLOY`.
    - If there have been any code changes, click `AUTO-COMMIT & DEPLOY` or commit yourself and click `REFRESH`, then `DEPLOY`
2. Wait for the streaming log to show "Deploy completed successfully".
3. Reload your live site.

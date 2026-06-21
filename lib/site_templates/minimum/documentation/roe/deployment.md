---
title: Deployment
status: published
url_name: deployment_old
---

# Deployment

Roe CMS supports two deployment targets: **[Fly.io](https://fly.io)** (recommended for most users) and **[Kamal](https://kamal-deploy.org/)** on a VPS like DigitalOcean (best if you want full control over your server). Both routes use Docker images under the hood, but Fly removes most of the server-side setup work — no SSH keys, no Docker Hub account, no provisioning. If you're not sure which to pick, start with Fly.

This document covers Fly.io first, then DigitalOcean + Kamal.

## Fly.io (Recommended)

Fly is the lightest-touch path to a live Roe site. You install one CLI tool (`flyctl`), sign in, click Deploy from Roe's admin, and Fly handles the rest — image builds, container hosting, persistent storage, SSL, and routing.

### Create a Fly Account

1. Go to [fly.io](https://fly.io) and sign up.
2. Add a payment method. Fly offers free credit for new accounts; small Roe sites typically run for a few dollars per month.

### Install flyctl

`flyctl` is Fly's command-line tool. Roe's admin Deploy button shells out to it.

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

```bash
fly apps create my-roe-site
```

If the name is taken, Fly will tell you and you can pick another.

### Configure Roe for Fly

In your local Roe admin: **Settings → Deployment**.

1. **Target**: select **Fly.io**.
2. **App name**: paste the name you just created (e.g. `my-roe-site`).
3. **Region**: choose a region close to you or your audience. `iad` (US East), `lhr` (London), `syd` (Sydney) are common choices. Run `fly platform regions` in your terminal for the full list.
4. **VM memory**: `1gb` is right for most sites. Bump to `2gb` if you see out-of-memory errors during deploys.
5. **Volume size (GB)**: how much disk to allocate for your `/site` folder, databases, and logs. Roe shows your current `/site` size and a suggested target — use the suggested value as a starting point.

Click **Save**. Roe writes `fly.toml` (Fly's config file) with your settings.

### Deploy

In **Admin → Updates & Deploy**, click **Deploy**. Roe runs `fly deploy` behind the scenes:

1. Builds a Docker image from your current Roe install.
2. Pushes it to Fly's registry.
3. Provisions the volume for your `/site` and database storage if it doesn't exist yet.
4. Starts a container running Roe.
5. Sets `RAILS_MASTER_KEY` and your admin credentials as Fly secrets, so the live container can decrypt config and let you log in immediately.

Expect 5–10 minutes for the first deploy. Subsequent deploys are faster (2–4 minutes) because Fly caches Docker layers.

The deploy log streams live in the admin panel — you'll see each step as it runs.

### Verify the Deploy

Once the deploy completes, your site is live at:

```
https://my-roe-site.fly.dev
```

Visit it in a browser. If your local site has content, push it across with Site Sync (covered below). If not, you'll see Roe's empty-site placeholder.

Sign in to the live admin at `https://my-roe-site.fly.dev/admin` using **the same email and password you use locally** — Roe bootstrapped your admin user as part of the first deploy.

### Push Your Site Content

The first deploy ships the Rails app but not your `/site` folder (your content). Send your local content to the live site via Site Sync:

1. On your local admin, go to **Site Sync**.
2. The Peer URL field should be pre-filled with your `https://my-roe-site.fly.dev` address. If not, paste it in and save.
3. Click **Refresh exchange**. You should see "Last contact with Live site: less than a minute ago" — that confirms the API connection works.
4. Click **Push to live**, type `LIVE` to confirm.

A few minutes later, your posts, pages, theme, and media are on production. Reload your live site to see them.

### Domain and SSL (when ready)

Fly issues a `https://<your-app>.fly.dev` URL automatically with SSL — you can launch with that. When you have a custom domain ready:

1. Add a custom domain via Fly's UI: **fly.io** → your app → **Certificates** → **Add a Certificate**.
2. Fly tells you exactly which DNS records to add (an `A` record and a `CNAME` for `www`). Add them via your DNS provider.
3. Within a few minutes Fly verifies the domain and issues a Let's Encrypt certificate automatically. Your site is now live at your custom domain with HTTPS.

No CLI commands needed — Fly handles the SSL setup entirely.

### Going Forward: Routine Deploys

After the first deploy, everything's set up. Routine deploys are one click:

1. In your local admin: **Updates & Deploy → Deploy**.
2. Wait for the streaming log to show "Deploy completed successfully".
3. Reload your live site to verify.

That's it — no SSH, no swap files, no SQLite lock cleanup. Fly handles container lifecycle and storage for you.

### Fly Troubleshooting

#### "fly: command not found"

The `flyctl` install didn't add `fly` to your PATH. Reopen your terminal, or run `source ~/.zshrc` (or `~/.bash_profile`) to pick up the updated PATH.

#### "Error: Could not list Fly secrets — fly auth login required"

Your session token expired. Run `fly auth login` again from your terminal, then retry the deploy.

#### Deploy hangs at "Machine checks"

Fly is restarting your container and waiting for it to pass health checks. If it takes more than five minutes, check the Fly dashboard for the app — there's usually a specific failure message there (out of memory, build error, etc.). The most common cause is running out of disk space on your volume; bump the volume size in Settings → Deployment.

#### "Clear deploy cache + retry"

If a deploy fails with a confusing error (especially "failed to compute cache key" or similar), use the "Clear deploy cache + retry" button on the failed-state panel. This forces a fresh build from scratch, which fixes most cache-related failures. The first build after a cache clear takes a few extra minutes.

---

## DigitalOcean

DigitalOcean has an excellent step-by-step article that explains [How To Set Up an Ubuntu Server on a DigitalOcean Droplet](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ubuntu-server-on-a-digitalocean-droplet). I would go through this article and below, I will include any Roe specific recommendations and instructions.

### Create an Account

1. Go to [DigitalOcean.com](https://www.digitalocean.com/) and click Menu → Products → Computer → Droplets
2. Add your name, email and password.
3. Signup

### Create a Droplet

1. Choose a datacenter region near you or your primary audience.
2. Choose an image (Ubuntu recommended)
3. Choose a Droplet Plan
    - Basic
    - Regular (if available in region. try Permium AMD or Premium Intel if Regular is not available.)
    - Lowest price possible for the size of your site (most sites should work with the 35GB plan.)
4. You can skip "Add additional storage" unless you have a very large site with tons of content.
5. Skip "Enable backups" unless you really need them. Roe takes care of backups for you.

## Authentication

### Add an SSH Key

If you're unfamiliar with how to create an SSH key, this article with DigitalOcean goes through it step-by-step for all platforms: [Create SSH Keys with OpenSSH on macOS, Linux, or Windows](https://www.digitalocean.com/community/tutorials/how-to-create-ssh-keys-with-openssh-on-macos-or-linux#step-3-generating-keys-with-openssh)

When you create the SSH, paste this command into your terminal:

```bash
ssh-keygen -t ed25519 -C "roe-do-deploy" -f ~/.ssh/roe_do
```

You can skip adding a `PASSPHRASE` or add one if you like.

This will create 2 SSH files on your system:

1. `/Users/<username>/.ssh/roe_do`
2. `/Users/<username>/.ssh/roe_do.pub`

Never share `roe_do`, this is your private key. `roe_do.pub` is the part you need to add to DigitalOcean (or any platform).

You can add this SSH key to your `ssh/config` so Kamal can automatically pick the right key without you having to remember every time. Copy and paste the command below into your terminal:

#### Mac/Linux

Make sure to replace the `DROPLET_IP` with your Public IP from DigitalOcean for this droplet.

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
DROPLET_IP="100.200.100.200"
cat >> ~/.ssh/config << EOF

Host $DROPLET_IP
  IdentityFile ~/.ssh/roe_do
  User root
EOF
chmod 600 ~/.ssh/config
```

#### Windows/PowerShell:

```bash
$DropletIP = "100.200.100.200"
New-Item -ItemType Directory -Force -Path "$HOME\.ssh" | Out-Null
@"

Host $DropletIP
  IdentityFile ~/.ssh/roe_do
  User root
"@ | Add-Content -Path "$HOME\.ssh\config"
```



#### Copy the public key to your clipboard so you can paste it into DigitalOcean:

**Mac**

```bash
pbcopy < ~/.ssh/roe_do.pub
```

**Linux**

```bash
xclip -selection clipboard < ~/.ssh/roe_do.pub
```

**Windows**

```bash
cat ~/.ssh/roe_do.pub | clip
```

Paste it into DigitalOcean's SSH key field when prompted.

### Additional

#### Enable Improved Metrics and monitoring

Free, gives you CPU/memory/disk graphs in the DO control panel. Highly recommended on small droplets where running out of memory is a real failure mode.

#### Don't enable Startup scripts

Kamal handles all the Roe-specific setup. Startup scripts add a layer that's hard to debug if something goes wrong on first boot.

---

## Connect to the Droplet

Once the droplet is created, you can sign in via SSH:

```bash
ssh root@100.200.100.200
```

Replace the numbers with your droplet's public IP address. You should land in a shell prompt without being asked for a password — that's because the `~/.ssh/config` entry from the previous step tells SSH which key to use automatically.

Type `exit` to leave `SSH` at any time.

## Prepare the Droplet

### Add a Swap File (recommended for small droplets)

This is only recommended if you're using a small droplet (1GB). Adding a 2GB swap file prevents the system from being overloaded. SSH into the droplet and paste this:

```bash
sudo swapon --show
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

The last command should show `Swap: 2.0Gi` in the output. The swap file persists across reboots thanks to the `/etc/fstab` line.

This article has more info about this fix: [Boosting Your DigitalOcean Droplet's Memory: No Upgrade Needed When You're Short on RAM](https://www.pablogarcor.com/boost-digitalocean-droplet-memory-without-upgrading/)

## Set Up a Docker Registry

Kamal builds the Roe image locally and pushes it to a [Docker registry](https://www.youtube.com/watch?v=2WDl10Wv5rs). The droplet pulls from there to deploy. **Docker Hub** is the easiest option for getting started.

### Create a Docker Hub Account

1. Go to [hub.docker.com](https://hub.docker.com) and sign up.
2. Verify your email.

### Generate a Personal Access Token

Don't use your account password — generate a dedicated token instead:

1. Docker Hub → **Account Settings → Personal Access Tokens → Generate New Token**
2. Description: `roe-kamal-deploy`
3. Expiration: `None` (or pick the longest option offered)
4. Permissions: **Read, Write, Delete** (Kamal needs all three)
5. Copy the token immediately — Docker Hub only shows it once

You'll paste this into `.kamal/secrets` shortly.

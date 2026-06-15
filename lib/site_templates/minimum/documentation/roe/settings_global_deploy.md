---
roe_version: 0.0.26
title: "Settings → Global: Deployment"
status: published
---

# Deploy Configuration

## Before you can deploy

The **[Updates & Deploy](/admin/updates)** page checks all settings before the `DEPLOY` button is active. If anything is missing, that page will list what you need to do.

**For any deploy target:**

- A **site URL** set in *Settings → Site* (e.g. `https://yoursite.com`).
- A `config/master.key` in your local Roe install. This is generated when you install/run Roe locally.

**For Kamal:**

- A **server** running a recent Linux distro with SSH access for `root`. Any provider works (DigitalOcean, Hetzner, Linode, etc.). Kamal will SSH in and install Docker/Roe automatically.
- Kamal uses Docker to deploy. You'll need a [Docker Registry](https://www.geeksforgeeks.org/devops/what-is-docker-registry/) to do this. We recommend [Docker Hub](https://hub.docker.com/) and you'll need to create your access token (Account Settings → Security → New Access Token. Grant it Read & Write access)
- The **Kamal CLI**, installed when you install/run Roe.

**For Fly.io:**

- A **Fly.io account** and the **flyctl CLI** installed (`brew install flyctl`) and authenticated (`fly auth login`).
- A **Fly app created in advance** — `fly apps create <name>`. Roe deploys to an existing app; it doesn't create one.

## Credentials

### Rails master key

Rails uses this key to decrypt anything encrypted on disk (credentials, secrets). It's auto-generated when Roe first boots and stored at `config/master.key`. Your production app needs the same key to read the same data — Kamal copies it to production when you deploy. The Deploy page detects whether a master key exists and offers to generate one if not.

### Registry password (Docker Hub access token)

To deploy with Kamal, create a Docker Hub account and generate an **Access Token** with **Read & Write** access (<https://hub.docker.com/settings/security>). Paste the token in: `Settings → Deploy → Credentials`. Roe stores it encrypted in the database and writes it to `.kamal/secrets` only during a deploy.

## Deployment Target

Right now, Roe supports 2 ways of deploying:

- `kamal` (standard Rails deployment)
- `fly` (Fly.io, managed hosting platform)

### Common settings

- **App name** — the name your container/app gets on Kamal or Fly. Defaults to the folder name of your local Roe install (e.g. `roe-0.1.0`), which usually isn't what you want — override to something stable like `mysite`. Lowercase, no spaces, hyphens OK.
- **Enable SSL/HTTPS** — leave on (default). Roe configures [Let's Encrypt](https://kamal-deploy.org/docs/configuration/proxy/#ssl) automatically once a custom domain is set and resolves. Until then you can still reach the deployed site over plain HTTP via the server's IP — SSL just won't kick in without a domain name.

### `kamal`

#### Servers

The **IP address** (or hostname) of your deploy target. Roe will SSH in as `root` to install Docker, pull the image from the registry, and run the install. You can add multiple servers for a multi-host deploy; most installs use one.

#### Custom domain

You'll need to setup your custom domain on whichever web host you choose. For the DNS settings, point an `A` record at your server's IP address; once DNS resolves, Kamal requests a Let's Encrypt certificate on the next deploy. SSL is automatic from there.

#### Registry username

Your Docker Hub username so Roe can find the image/repository.

#### Repository name

The name of the Docker image Kamal pushes to Docker Hub (e.g. `mysite`). Defaults to your root folder name if blank. The full image path is `<registry username>/<repository name>`.

### `fly` (fly.io)

#### Region

Three-letter Fly region code for your primary deployment — `iad` (Virginia), `sjc` (San Jose), `ams` (Amsterdam), etc. See <https://fly.io/docs/reference/regions/> for the full list. Defaults to `iad` if blank.

#### VM memory

RAM for your site's VM. `1GB` is enough for most Roe sites; bump to `2GB` if traffic is heavy or things seem suddenly slow. Can be changed at any time without losing data.

#### Volume size

The persistent disk allocated to `/site` and your SQLite database. Start at `2GB` and grow as your media library does. Roe **warns** you in the admin when you're approaching the volume's limit; growing the volume itself is one command: `fly volumes extend <volume-id> --size <new-GB>`.

---
title: "Troubleshooting → Deployment"
status: published
url_name: troubleshoot-deployment
related:
  - guide-deploy
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Troubleshooting Roe Deployment

## Fly Troubleshooting

If any of these don't help, please visit: [Support](/support) and we'll get you sorted.

#### fly: command not found

The `flyctl` install didn't add `fly` to your PATH. Reopen your terminal, or run `source ~/.zshrc` (or `~/.bash_profile`) to pick up the updated PATH.

#### You're not signed in to Fly
{: #fly-signed-out}

Your session expired, or you haven't signed in on this computer yet. Roe checks before a deploy starts, because `fly deploy` without a session produces no output and never finishes — it looks like a hang rather than a failure.

1. Open a terminal. Any folder will do.
2. Run `fly auth login`. It opens your browser.
3. Sign in. You'll see "Your CLI is connected now. Feel free to close this tab."
4. Back in the terminal you'll see `successfully logged in as <your email>`.
5. Deploy again.

The older message **Could not list Fly secrets — fly auth login required** means the same thing.

#### Roe couldn't reach Fly
{: #fly-unreachable}

The `fly` command couldn't get an answer from Fly's API, so there's no way to tell whether you're signed in. Signing in again won't help — `fly auth login` uses the same connection and fails the same way. A typical error looks like:

```
Error: Post "https://api.fly.io/api/v1/cli_sessions": EOF
```

`EOF` means the connection closed before Fly answered. You may also see `i/o timeout`, `no such host`, or `dial tcp`.

Work through these in order:

1. **Try again in a minute**. This is often momentary, and a retry works.
2. **Confirm it isn't an issue with Roe**. Run fly auth whoami directly in a terminal. This should return the email address used to sign into Fly.
3. **Check status.fly.io**. If Fly is having an incident we know it's not on Roe's side.
4. **Turn off any VPN, then retry**. VPNs can block or intercept API traffic.
5. **Try a different network**. Work and school networks may filter outbound connections. Tethering to your phone is a quick way to route around that issue.

If `fly auth whoami` works in the terminal but Roe still reports it can't reach Fly, that's worth reporting — see [Support](/support).

#### Deploy hangs at "Machine checks"

Fly is restarting your container and waiting for it to pass health checks. If it takes more than five minutes, check the Fly dashboard for the app — there's usually a specific failure message there (out of memory, build error, etc.). If it's cryptic, reach out and we'll help.

#### "Clear deploy cache + retry"

If a deploy fails with a confusing error (especially "failed to compute cache key" or similar), use the "Clear deploy cache + retry" button on the failed-state panel. This forces a fresh build from scratch, which fixes most cache-related failures. The first build after a cache clear takes a few extra minutes.

---

## Troubleshooting Kamal

### Tailwind CSS errors after deploy ("asset 'tailwind.css' was not found")

If you've made local changes to assets, ensure they're committed to git before deploying — Kamal versions images by git SHA. If the SHA hasn't changed, Kamal may reuse a cached build that misses your new assets.

If the issue persists after committing, the Docker layer cache may have stale state. Force a fresh build:

```bash
ssh root@<your-droplet-ip> 'docker builder prune -a -f && docker buildx prune -a -f'
kamal deploy
```

### Container fails health check / "target failed to become healthy within configured timeout (30s)"

Usually a SQLite lock issue. Stale write-ahead-log files left over from a crashed previous container can prevent the new one from booting. Recovery:

```bash
kamal app stop
ssh root@<your-droplet-ip> 'cd /var/lib/roe/site/db/production && rm -f *-wal *-shm'
kamal deploy
```

### Droplet becomes unresponsive during deploy

The 1GB plan can run out of memory during the build + container restart cycle. If SSH stops responding:

1. **Power Cycle** the droplet from the DigitalOcean dashboard (Power → Power Cycle).
2. Wait ~30 seconds.
3. SSH back in.
4. Make sure the swap file from earlier is active: `free -h` should show 2GB of swap.

If this happens repeatedly, consider upgrading to the 2GB plan ($12/mo) — the extra RAM gives you headroom during deploys. The resize is reversible and doesn't lose data.

### "No such file: config/master.key" errors

The master key wasn't created or wasn't shipped to the container. Check that `config/master.key` exists locally and contains the right value, and that `.kamal/secrets` has the line `RAILS_MASTER_KEY=$(cat config/master.key)`.

### Need to roll back to a previous version

Kamal tags every image in your registry. To roll back:

```bash
kamal app boot --version=<previous-tag>
```

Find the previous tag in your Docker Hub repository's tags list, or via `kamal app version`.

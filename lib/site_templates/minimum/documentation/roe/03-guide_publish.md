---
title: Guide → Publish a static site
status: published
url_name: guide-publish
tags: guide, publish
related:
  - site-sync
  - guide-deploy
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# How to publish a Static Site

Roe publishes static sites through [Site Sync](/documentation/roe/site-sync). You have three ways to get your files onto a host:

1. Download a ZIP of your site and upload it to your host yourself.
2. [SFTP](/documentation/roe/glossary#sftp-ssh-file-transfer-protocol) — SSH File Transfer Protocol.
3. [FTPS](/documentation/roe/glossary#ftps-file-transfer-protocol-ssl) — File Transfer Protocol Secure.

Most hosts offer at least one of these. Check your host's documentation to see which they support.

**SFTP** is the recommended option. Set it up once, and Roe pushes only your changed files each time you publish.

## Download a ZIP of your site

You can download a ZIP of your entire `site/` folder at any time — as a backup, or to upload to a host by hand.

1. Go to [Site Sync → Static Site Sync](http://localhost:3000/admin/site_sync?tab=static-sync).
2. Choose the **ZIP download** option.
3. Click **DOWNLOAD ZIP**.

## Set up SFTP (recommended)

1. Go to [Site Sync → Static Site Sync](http://localhost:3000/admin/site_sync?tab=static-sync).
2. Choose **SFTP**.
3. **Host** — the SFTP host from your hosting provider.
4. **Port** — 22.
5. **Username** — your hosting account username (for example, your cPanel account), not an FTP account.
6. **SSH private key** — paste your private key, including its `BEGIN` and `END` lines.
7. **Key passphrase** — if you set a passphrase when you created the key, enter it here. Otherwise leave it blank.
8. **Remote path** — the folder on your host to publish into. This is commonly `public_html`, but it varies by host.
9. Click **Save**.

Roe stores your key and passphrase encrypted and never shows them again. Use the `UPDATE` button to change the key or passphrase.

## Set up FTPS

FTPS is the most widely supported protocol, so reach for it when your host doesn't offer SFTP.

1. Go to [Site Sync → Static Site Sync](http://localhost:3000/admin/site_sync?tab=static-sync).
2. Choose **FTPS**.
3. **Host** — the FTP host from your hosting provider.
4. **Port** — 21.
5. **Username** — your FTP account username, often in the form `user@domain`.
6. **Password** — your FTP account password. Roe stores it encrypted.
7. **Remote path** — the folder on your host to publish into, commonly `public_html`.
8. Click **Save**.

Roe verifies the host's [TLS](/documentation/roe/glossary#tls-ssl-transport-security-layer-secure-socket-layers) certificate automatically. Some shared and cPanel hosts present a self-signed or mismatched certificate, which verification rejects. When that happens, **Test Connection** shows a prompt to connect without verification. The connection stays encrypted either way — skipping verification only means Roe doesn't confirm the host's identity.

## Publish your site

Once SFTP or FTPS is connected, publishing takes three steps.

1. **Rebuild the static site.** Open **Static Site Actions** (linked from the Static Site Sync panel) and click **Rebuild (Clean + Generate)** so the output reflects your latest content.
2. **Test the connection.** Click **TEST CONNECTION** to confirm Roe can reach your host with the credentials you saved.
3. **Push.** Click **PUSH NOW**. The first push uploads every file; after that, Roe uploads only the files that changed since your last push. A progress panel shows each file as it transfers.

If your host and Roe's record of it ever drift apart, click **FULL RE-SYNC**. It re-uploads every file and removes any file Roe previously pushed that no longer exists locally. Use it to recover, not for everyday publishing.

ZIP download has no push step — you upload the downloaded file to your host yourself.

## Helpful documentation links

### cPanel

cPanel allows you to create SSH Keys. We recommend creating the key in cPanel and then adding it to Roe:

#### Create your SSH Key in cPanel

1. Sign into your cPanel
2. Find to SSH Access tool in the Security section and click it
3. Click "Manage SSH Keys"
4. Click "+ Generate a New Key"
5. Fill in these options:
    - Key Name: `id_rsa_roe`
    - Password: add your own passphrase or password and save it in a safe place
    - Key Type: `RSA`
    - Key size: `2048`
6. Click "Generate Key" 
7. It will confirm the Key's creation, click "← Go Back"

You will see your new key as a Public Key and a Private Key

#### Add your SSH Key from cPanel to Roe

**In cPanel:**

1. Click "🔧 Manage" for the Public Key: `id_rsa_roe`
2. Click "Authorize" and click "← Go Back"
3. Click "View/Download" for the Private Key: `id_rsa_roe`
4. Copy everything in the "Private SSH Key “id_rsa_roe” Open Key" box.

**In Roe:**

Follow the steps outlined above for [SFTP](#set-up-sftp-recommended).

Many hosts install cPanel to manage your site. These pages will help:

- [How to Configure Your SFTP Client](https://docs.cpanel.net/knowledge-base/ftp/how-to-configure-your-sftp-client/)
- [Manage SSH keys](https://docs.cpanel.net/cpanel/security/ssh-access#manage-ssh-keys)
- [File Manager](https://docs.cpanel.net/cpanel/files/file-manager/)

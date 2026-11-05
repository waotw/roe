---
title: "Guide: Installation"
status: published
url_name: guide-installation
tags: guide, getting-started
related:
  - getting-started-with-roe
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Installing Roe

Roe is installed with a single command in the terminal. The installer explains each step and checks before it does anything.

Roe will install the tools it needs to run. It only does this once. After that, you can add more Roe sites without installing anything else. The full list of tools is in [Requirements for Roe](/documentation/roe/roe-requirements).

## Install with a single command

### Mac and Linux

 open Terminal and run:

```bash
cd ~ && curl -fsSL https://go-roe.com/install | bash
```

### Windows

Open PowerShell as Administrator and run:

```bash
irm https://go-roe.com/install.ps1 | iex
```

Then follow the prompts. Details for each operating system below: [macOS](#macos), [Linux](#linux) and [Windows](#windows).

==Note:== If you stop partway through the installation, don't run the one-line command again: it downloads a new Roe folder. Instead, open the Roe folder in your Terminal, [instructions below](#install-roe-manually), and run `./roe.sh install`. This will pick up the installation and skip what was already done.

### What the installer does

1. Downloads the latest Roe release and unpacks it into a folder in your home folder.
2. Offers to rename the Roe folder.
3. Checks your computer for what Roe needs and installs anything missing.
4. Sets up Roe and your site.
5. Installs the `roe` command and gives your site its own address, such as `http://my-site.roe`. Your computer asks for your password to add the address.
6. Starts Roe and opens your site and its admin in your browser.

### macOS

- **Opening Terminal:** press `command` + `space`, type `terminal` and press `return`.
- **Command Line Tools:** if needed, macOS installs Apple's Command Line Tools in a separate window. This takes 5–10 minutes. When it has finished, go back to Terminal and press `c`.
- **Password:** the password prompt is for your Mac login, not for Roe.

### Linux

- **unzip:** the installer needs `curl` and `unzip`. If `unzip` is missing, install it with your package manager (for example, `sudo apt-get install unzip`) and run the command again.
- **Build tools:** if your system has no C compiler or `make`, the installer shows the command for your distribution. Run it in a second terminal, then press `c`.
- **Password:** the password prompt is for your Linux account (`sudo`).

### Windows

Roe runs on Windows inside **WSL**, a Linux system built into Windows 10 and 11. The installer sets WSL up, then runs the same installer as Mac and Linux.

- **Opening PowerShell as Administrator:** press the `Windows` key, type `powershell`, right-click **Windows PowerShell**, choose `Run as administrator`, then click `Yes`.
- **Restart:** if WSL isn't installed yet, Windows needs a restart. Restart, then run the same command again.
- **Linux username:** the first time Linux starts, it asks for a username and password. They're only used inside Linux. <mark>Write the password down.</mark> The installer asks for it when installing tools.
- **Your site's address:** Roe shows a line to add to your Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`, opened as Administrator). Until you add it, use `http://localhost:3000`.

#### Where your files are

Roe must stay in your Linux home folder. Windows drives (`C:`) can't store the file permissions Roe needs, and Roe can't see changes made to files there. Roe checks for this and stops if it's on a Windows drive.

To open your files from Windows, paste this into File Explorer's address bar:

`\\wsl$\Ubuntu\home\your-username\`

#### Editing files from Windows

Use [Visual Studio Code](https://code.visualstudio.com) with its **WSL** extension. Open the Ubuntu app from the Start menu and run `code ~/your-roe-folder`.

#### Starting Roe later

Open the **Ubuntu** app and run `roe start`.

## Install Roe manually

You can install Roe without the one-line command:

1. [Download Roe](https://github.com/waotw/roe/releases/latest/download/roe.zip) and unzip it.
2. Rename the folder and move it where you want to keep your site.
3. Open Terminal in that folder: type `cd`, a space, drag the folder onto the Terminal window, and press `return`.
4. Run `./roe.sh install`.

From step 3 of [What the installer does](#what-the-installer-does), the steps are the same.

The folder holds two main folders:

- `/current`: the Roe application.
- `/site`: your content, settings and databases.

## Next

Sign in with your admin user, then see [Getting Started with Roe](/documentation/roe/getting-started-with-roe).

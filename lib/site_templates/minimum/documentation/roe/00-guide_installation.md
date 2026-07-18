---
title: Guide → Installation
status: draft
url_name: guide-installation-old
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

Roe is an application built with [Ruby on Rails](/documentation/roe/glossary#ruby-on-rails). In order to use Roe locally, you'll need to install Ruby and a few supporting tools. This is the biggest hurdle to using Roe, well worth it, and once it's done, you can create as many Roe sites as you want without having to reinstall anything.

Currently, I have not tested Roe on Windows. If you're interested in getting it working, I would love the help: [roe@weareontheweb.com](mailto:roe@weareontheweb.com)

## First) [Download Roe](https://codeberg.org/waotw/roe/releases/download/v0.0.37/roe-0.0.37.zip)

Roe contains two folders: `/current` (the app/code) and `/site` (all your site content, configuration, and databases) as well as a few other files.

[Install on Linux](#linux)

## macOS

1. Find the downloaded zip file, unzip it (this is "Roe folder"), and move it to a folder on your computer where you want to keep your website.
2. Launch your Terminal app:
    - hold down `command` + `space`, this will open Spotlight.
    - type `terminal`, the Terminal app show up, hit `return`
3. Open the Roe folder in the Terminal
    - In Terminal, type `cd` and hit `space`, do not press `return` yet.
    - Drag and drop the Roe Folder onto the Terminal (it will drop the location of that folder into the Terminal)
    - Hit `return`
4. In the Terminal type `./roe.sh check` into the terminal and press `return`.
5. **Installing Ruby:** the script will check what's already installed and then ask to install anything missing.
    - When you see `Install now? [y/q]`, type `y` and press `return`.
    - The script installs [mise](/documentation/roe/glossary#mise) (a tool for installing programming languages) and the correct Ruby version for Roe.
    - <mark>Note:</mark> on a fresh Mac, you may be prompted to install Apple's Command Line Tools. macOS will show a separate installer window; when it finishes, return to the terminal and press `c` to continue.
    - Some steps take a few minutes the first time. Wait until the terminal prompt is back and you see: `[✓] Ready — Ruby and Git are in place.`
6. **Roe setup:** you'll see `Next step: Run the Roe setup`, type `y` and press `return`.
    - The setup runs as an interactive progress screen: it installs [gems](/documentation/roe/glossary#gems), creates your `/site` folder, prepares the database, generates default configuration, and syncs content.
7. **Admin user:** once setup finishes, you'll see the admin user setup:
    - Enter the email you want to use for Roe
    - Choose whether to use a random or manual password.
    - <mark>Note:</mark> either way, write this down in a safe place. If you chose a random password, you will only see it once.
8. Recovery codes: write these down in a safe place, <mark>you won't ever see them again.</mark>
    - These codes are used to reset your password if needed.
9. Once you've written everything down (or saved it), press any key to continue.
10. Press `y` and hit `return`…
11. The server starts automatically and opens Roe in your browser.
12. Sign in with the admin user you just created.

Check [Getting Started with Roe](/documentation/roe/getting-started-with-roe) for some help exploring Roe.

## Linux

1. Find the downloaded zip folder, unzip it, and move it to a folder on your computer where you want to keep your website.
2. Open the Roe folder in your terminal. You can do this with `cd`. If the Roe folder is in your home directory, you can use this: 

    `cd ~/roe-folder-name`

    Most Linux file managers can also launch a terminal in the current folder. The exact menu name varies by distribution:

    - **GNOME Files (Nautilus)** — right-click inside the Roe folder and select `Open in Terminal`. If you don't see this option, install the helper: `sudo apt-get install nautilus-extension-gnome-terminal` (Ubuntu/Debian) or the equivalent for your distro.
    - **KDE Dolphin** — open the Roe folder, then press `F4` to drop into an embedded terminal already pointed at it. Or right-click and select `Open Terminal Here`.
    - **Other file managers** — most have a similar `Open Terminal Here` option in the right-click menu. If not, fall back to opening a terminal manually and `cd`-ing into the folder.

    If your distribution doesn't ship one of these by default, this document is a good general reference: [How to Open a Folder in Linux](https://linuxvox.com/blog/how-to-open-folder-in-linux/).
3. Type `./roe.sh check` into the terminal and press `enter`.
4. **Installing Ruby:** the script will check what's already installed and then ask to install anything missing.
    - When you see `Install now? [y/q]`, type `y` and press `enter`.
    - The script installs [mise](/documentation/roe/glossary#mise) (a small version manager) and the correct Ruby version for you.
    - <mark>Note for Linux:</mark> if your system is missing the C compiler and `make` needed to build Ruby's libraries, the script shows the install command for your distribution (Debian/Ubuntu `apt-get`, Fedora/RHEL `dnf`, Arch `pacman`, etc.). Copy it, run it in another terminal, then return here and press `c` to continue.
    - Some steps take a few minutes the first time. Wait until you see: `[✓] Ready — Ruby and Git are in place.`
5. **Roe setup:** you'll see `Next step: Run the Roe setup`, type `y` and press `enter`.
    - The setup runs as an interactive progress screen: it installs [gems](/documentation/roe/glossary#gems), creates your `/site` folder, prepares the database, generates default configuration, and syncs content.
6. **Admin user:** once setup finishes, you'll see the admin user setup:
    - Enter the email you want to use for Roe
    - Choose whether to use a random or manual password.
    - <mark>Note:</mark> either way, write this down in a safe place. If you chose a random password, the script shows it once.
7. Recovery codes: write these down in a safe place, <mark>you won't ever see them again</mark>
    - These codes are used to reset your password if needed.
8. Once you've written everything down (or saved it), press any key to continue.
9. The server starts automatically and opens Roe in your browser.
10. Sign in with the admin user you just created.

## You're done

Check [Getting Started with Roe](/documentation/roe/getting-started-with-roe) for next steps.

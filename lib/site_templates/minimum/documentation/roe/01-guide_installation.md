---
title: Guide → Installation
status: published
url_name: guide-installation
tags: guide
related:
  - getting-started-with-roe-cms
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Installing Roe

Roe is an application built with [Ruby on Rails](/documentation/glossary#ruby-on-rails). In order to use Roe locally, you'll need to install a few tools on your computer as well as Rails. This is the biggest hurdle to using Roe, well worth it, and once it's done, you can create as many Roe sites as you want without having to reinstall anything.

Currently, I have not tested Roe on Windows. If you're interested in getting it working, I would love the help: [roe@weareontheweb.com](mailto:roe@weareontheweb.com)

## First) [Download Roe](https://codeberg.org/waotw/roe/releases/download/v0.0.36/roe-0.0.36.zip)

Roe contains two folders: `/current` (the app/code) and `/site` (all your site content, configuration, and databases) as well as a few other files.

[Install on Linux](#linux)

## macOS

1. Find the downloaded zip folder, unzip it, and move it to a folder on your computer where you want to keep your website.
2. Make sure you have breadcrumbs visible on your Finder window (select `View > Show Path Bar` from the top menu of Finder).
3. Right-click the Roe folder in the breadcrumb path and choose `Open in Terminal`.
    - ![Finder Path Bar](/media/images/finder-path-roe.png)
    - ![Finder Path Bar](/media/images/finder-path-roe-menu.png)
4. Type `./roe.sh check` into the terminal and press `return`.
5. **Installing Tools:** follow the prompts, and type `(c)` then `enter/return` to continue.
    - <mark>Note:</mark> some of these can take a bit. Wait until it finishes. The terminal prompt will be present (`username@computer-name ~ %`) when it's time to move on.
    - Once the tools are installed, you will see this message: `[✓] All required dependencies are installed!`
6. **Roe setup:** you'll see `Next step: Run the Roe setup`, type `y` and press `enter/return`.
    - All required [gems](/documentation/glossary#gems) will be installed, your `/site` folder and other assets will be created.
7. **Admin user:** Once that's done, you'll see: `No admin user found. Let's create one…`
    - Enter the email you want to use for Roe
    - Choose whether to use a random or manual password.
    - <mark>Note:</mark> either way, write this down in a safe place.
8. Recovery codes: write these down in a safe place, <mark>you won't ever see them again</mark>
    - These codes are used to reset your password if needed.
9. Once you've written everything down (or saved it), press `return` to continue.
10. Type `y` and hit `return` to start the Roe server and open Roe in your browser automatically.
11. Sign in with the admin user you just created.

Check [Getting Started with Roe](/documentation/getting-started-with-roe-cms) for some help exploring Roe.

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
4. **Installing Tools:** follow the prompts, and type `(c)` then `enter` to continue.
    - <mark>Note:</mark> some of these can take a bit. Wait until it finishes.
    - <mark>Note for Linux:</mark> the script will show install commands for both Debian/Ubuntu (`apt-get`) and Fedora/RHEL (`dnf`) — copy and run the one for your distribution.
    - This is a helpful article about Linux package managers: [Comparison of major Linux package management systems](https://linuxconfig.org/comparison-of-major-linux-package-management-systems)
    - Once the tools are installed, you will see this message: `[✓] All required dependencies are installed!`
5. **Roe setup:** you'll see `Next step: Run the Roe setup`, type `y` and press `enter`.
    - All required [gems](/documentation/glossary#gems) will be installed, the databases and other assets will be created.
6. **Admin user:** Once that's done, you'll see: `No admin user found. Let's create one…`
    - Enter the email you want to use for Roe
    - Choose whether to use a random or manual password.
    - <mark>Note:</mark> either way, write this down in a safe place.
7. Recovery codes: write these down in a safe place, <mark>you won't ever see them again</mark>
    - These codes are used to reset your password if needed.
8. Once you've written everything down (or saved it), press `enter` to continue.
9. Type `y` and hit `enter` to start the Roe server and open Roe in your browser automatically.
10. Sign in with the admin user you just created.

## You're done

Check [Getting Started with Roe](/documentation/getting-started-with-roe-cms) for next steps.

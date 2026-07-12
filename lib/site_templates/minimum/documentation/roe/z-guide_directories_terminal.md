---
title: Guide → Find your Roe Folder
status: unlisted
url_name: guide-roe-folder
tags:
---

# Find the Roe folder

## macOS

1. Launch your Terminal app:
    - hold down `command` + `space`, this will open Spotlight.
    - type `terminal`, the Terminal app show up, hit `return`
2. Open the Roe folder in the Terminal
    - In Terminal, type `cd` and hit `space`, do not press `return` yet.
    - Drag and drop the Roe Folder onto the Terminal (it will drop the location of that folder into the Terminal)
    - Hit `return`

## Linux

If the Roe folder is in your home directory, you can use this: 

`cd ~/roe-folder-name`

Most Linux file managers can also launch a terminal in the current folder. The exact menu name varies by distribution:

- **GNOME Files (Nautilus)** — right-click inside the Roe folder and select `Open in Terminal`. If you don't see this option, install the helper: `sudo apt-get install nautilus-extension-gnome-terminal` (Ubuntu/Debian) or the equivalent for your distro.
- **KDE Dolphin** — open the Roe folder, then press `F4` to drop into an embedded terminal already pointed at it. Or right-click and select `Open Terminal Here`.
- **Other file managers** — most have a similar `Open Terminal Here` option in the right-click menu. If not, fall back to opening a terminal manually and `cd`-ing into the folder.

If your distribution doesn't ship one of these by default, this document is a good general reference: [How to Open a Folder in Linux](https://linuxvox.com/blog/how-to-open-folder-in-linux/).

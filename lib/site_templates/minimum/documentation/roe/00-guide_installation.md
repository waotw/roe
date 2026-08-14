---
title: Guide → Installation
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

Roe runs on your own computer. Before you can use it, Roe will install the tools it needs to run. You can see a list of all tools here: [Requirements for Roe](/documentation/roe/roe-requirements)

This is the biggest step in getting started — and you only take it once. After Roe is installed, you can create as many Roe sites as you like without installing anything again.

You won't do the work by hand. Roe has a friendly installer script that checks what your computer already has, installs only what's missing, and tells what each section is doing and when it is done.

These instructions cover macOS, Linux, and Windows. Windows support is new and I'm still gathering feedback on it — if you hit something these steps don't cover, I'd love to hear from you: [roe@weareontheweb.com](mailto:roe@weareontheweb.com).

## Download Roe

[Download Roe](https://codeberg.org/waotw/roe/releases/download/v0.2.0/roe-0.2.0.zip).

The download is a single zip file. Inside it are two main folders, plus a few supporting files:

- `/current` — the Roe application itself (its code)
- `/site` — everything that belongs to you: your content, settings, and databases

Now follow the steps for your computer:

- [Install on a Mac](#install-on-a-mac)
- [Install on Linux](#install-on-linux)
- [Install on Windows](#install-on-windows)

<mark>Note for Windows:</mark> you don't need the download above. Roe installs itself in one command — skip to [Install on Windows](#install-on-windows).

## Install on a Mac

1. Unzip the file you downloaded. Move the unzipped **Roe folder** wherever you'd like to keep your website on your computer.
2. Open the Terminal app.
    - Hold down `command` + `space` to open Spotlight.
    - Type `terminal` and press `return`. The Terminal opens.
3. Point the Terminal at your Roe folder.
    - Type `cd` followed by a space. Don't press `return` yet.
    - Drag the Roe folder onto the Terminal window. Its location drops in after `cd`.
    - Press `return`.
4. Type `./roe.sh check` and press `return`. The script checks what's already installed.
5. **Install system tools.** The script lists anything missing and offers to install it.
    - When you see `Install now? [y/q]`, type `y` and press `return`.
    - You can see a list of all tools used by Roe [here](/documentation/roe/roe-requirements) 
    - <mark>Note:</mark> on a fresh Mac, macOS may ask to install Apple's Command Line Tools in a separate window. Let that installer finish, then return to the Terminal and press `c` to continue.
    - The first run takes a few minutes. Wait until the prompt returns and you see `[✓] Ready — Ruby and Git are in place.`
6. **Run the Roe setup.** When you see `Next step: Run the Roe setup`, type `y` and press `return`.
    - A progress screen appears. Setup installs Roe related [tools](/documentation/roe/roe-requirements#the-ruby-gems-roe-installs), creates your `/site` folder, prepares the database, generates default settings, and basic content.
7. **Create your admin user.** When setup finishes, Roe asks for your account details.
    - Enter the email you want to sign in with.
    - Choose a random or a manual password.
    - <mark>Write your password down somewhere safe.</mark> If you choose a random one, Roe shows it only once.
    - **Save your recovery codes.** Roe shows them next. <mark>Write these down too — you won't ever see them again.</mark> They let you reset your password if you lose it.
    - Once everything is written down and saved, press any key to continue.
8. Press `y` and `return` to start Roe.
9. Roe starts the server and opens in your browser.
10. Sign in with the admin user you just created.

That's it — Roe is running. See [Getting Started with Roe](/documentation/roe/getting-started-with-roe) to start exploring.

## Install on Linux

1. Unzip the file you downloaded. Move the unzipped Roe folder wherever you'd like to keep your website.
2. Open the Roe folder in your terminal.

    You can do this with `cd`. If the Roe folder is in your home directory, use:

    `cd ~/roe-folder-name`

    Most Linux file managers can also open a terminal already pointed at the current folder. The menu name varies by distribution:

    - **GNOME Files (Nautilus)** — right-click inside the Roe folder and select `Open in Terminal`. If you don't see this option, install the helper: `sudo apt-get install nautilus-extension-gnome-terminal` (Ubuntu/Debian), or the equivalent for your distro.
    - **KDE Dolphin** — open the Roe folder and press `F4` to drop into an embedded terminal already pointed at it. Or right-click and select `Open Terminal Here`.
    - **Other file managers** — most have a similar `Open Terminal Here` option in the right-click menu. If not, open a terminal manually and `cd` into the folder.

    If your distribution doesn't ship one of these, this is a good general reference: [How to Open a Folder in Linux](https://linuxvox.com/blog/how-to-open-folder-in-linux/).
3. Type `./roe.sh check` and press `enter`. The script checks what's already installed.
4. **Install system tools.** The script lists anything missing and offers to install it.
    - When you see `Install now? [y/q]`, type `y` and press `enter`.
    - You can see a list of all tools used by Roe [here](/documentation/roe/roe-requirements).
    - <mark>Note for Linux:</mark> if your system is missing the C compiler and `make` that Ruby needs to build its libraries, the script shows the install command for your distribution (Debian/Ubuntu `apt-get`, Fedora/RHEL `dnf`, Arch `pacman`, and so on). Copy it, run it in another terminal, then return here and press `c` to continue.
    - The first run takes a few minutes. Wait until you see `[✓] Ready — Ruby and Git are in place.`
5. **Run the Roe setup.** When you see `Next step: Run the Roe setup`, type `y` and press `enter`.
    - A progress screen appears. Setup installs Roe related [tools](/documentation/roe/roe-requirements#the-ruby-gems-roe-installs), creates your `/site` folder, prepares the database, generates default settings, and basic content.
6. **Create your admin user.** When setup finishes, Roe asks for your account details.
    - Enter the email you want to sign in with.
    - Choose a random or a manual password.
    - <mark>Write your password down somewhere safe.</mark> If you choose a random one, the script shows it only once.
    - **Save your recovery codes.** Roe shows them next. <mark>Write these down too — you won't ever see them again.</mark> They let you reset your password if you lose it.
    - Once everything is written down and saved, press any key to continue.
7. Press `y` and `enter` to start Roe.
8. Roe starts the server and opens in your browser.
9. Sign in with the admin user you just created.

## Install on Windows

Roe runs on Windows inside **WSL** — a full Linux system that Microsoft builds into Windows 10 and 11. You don't need to know anything about Linux to use it. Windows installs it for you, and from then on Roe behaves exactly as it does on a Mac.

One command sets up everything, including Roe itself.

1. Open **PowerShell as Administrator**.
    - Press the `Windows` key and type `powershell`.
    - Right-click **Windows PowerShell** and choose `Run as administrator`.
    - Click `Yes` when Windows asks for permission.
2. Copy this line, paste it into PowerShell, and press `enter`:

    `irm https://go-roe.com/install.ps1 | iex`

3. **If Windows needs to install Linux first**, the script sets it up and asks you to restart.
    - Restart your computer.
    - Open PowerShell as Administrator again and run the same command a second time.
    - <mark>Note:</mark> this restart is required by Windows, not by Roe. Once it's done, you never need it again.
4. **Create your Linux username** if you're asked for one. This happens the first time Linux starts.
    - Pick any username and password you like. They're only used inside Linux.
    - <mark>Write the password down.</mark> Linux asks for it when installing tools.
5. The script installs Roe into your Linux home folder and hands over to the Roe installer. From here, everything matches the Mac and Linux steps above:
    - **Install system tools.** When you see `Install now? [y/q]`, type `y` and press `enter`. The first run takes a few minutes. Wait for `[✓] Ready — Ruby and Git are in place.`
    - **Run the Roe setup.** When you see `Next step: Run the Roe setup`, type `y` and press `enter`.
    - **Create your admin user.** Enter your email, choose a password, and <mark>write down your password and your recovery codes</mark> — you won't see the codes again.
    - Press `y` and `enter` to start Roe.
6. Roe opens in your normal Windows browser at `http://localhost:3000`.
7. Sign in with the admin user you just created.

### Where your files live

Roe installs into your Linux home folder, and it needs to stay there. Windows drives (your `C:` drive) can't store the file permissions Roe needs, and they hide file changes from Roe — so your edits would quietly stop appearing on your site. Roe checks for this and stops with instructions rather than letting you find out later.

Your files are still yours, and Windows can see them. Open File Explorer and paste this into the address bar:

`\\wsl$\Ubuntu\home\your-username\`

You'll find your Roe folder there, with `/site` inside it — the same folder Mac and Linux users have.

### Editing your files from Windows

The friendliest way is [Visual Studio Code](https://code.visualstudio.com):

1. Install VS Code on Windows.
2. Install its **WSL** extension (search for `WSL` in the Extensions panel).
3. Open the Ubuntu app from your Start menu and type: `code ~/roe-folder-name`

VS Code opens on Windows while your files stay on the Linux side, which keeps everything working as it should.

### Starting Roe again later

Open the **Ubuntu** app from your Start menu, then:

`cd ~/roe-folder-name && ./roe.sh start`

## You're done

Roe is installed and running. See [Getting Started with Roe](/documentation/roe/getting-started-with-roe) for your next steps.

---
title: Guide → Installation
status: published
url_name: guide-installation
tags: guide
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Installing Roe

Roe is an application built with [Ruby on Rails](/documentation/glossary#ruby-on-rails). In order to use Roe locally, you'll need to install a few tools on your computer as well as Rails. This is the biggest hurdle to using Roe, well worth it and once it's done, you can create as many Roe sites as you want without having to reinstall anything.

Currently, I have not tested Roe on Windows. If you're interested in getting it working, I would love the help: [roe@weareontheweb.com](mailto:roe@weareontheweb.com)

## 1. [Download Roe](# link needed /bw)

Roe is just a folder that contains 2 important folders: `/current` (the app/code) and `/site` (all your site content, configuation, and databases) as well as a few other files. When you download it, you'll see the `roe-v…` folder, you can name this anything you like or leave it as is.

If you decide to rename the `roe-v…` folder, just note what you called it.


## Open the Roe folder in your terminal

### Linux

If you're on [Linux](/documentation/glossary#linux), this document will help: [How to Open a Folder in Linux](https://linuxvox.com/blog/how-to-open-folder-in-linux/)

### Mac

#### Terminal

On Mac, you can do this with `cd` in the terminal which means `change directory`. If the Roe folder is in your user directory, you can use this:

```bash
cd ~/roe-folder-name
```

#### Finder

You can also use the Finder:

1. In the Mac menu for Finder, select `View → Show Path Bar`
2. You'll see the Roe folder at the bottom of the window, right click it and select `Open in Terminal`

![Finder Path Bar](/roe/media/finder-path-roe.png)

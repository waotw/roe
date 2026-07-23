---
title: How to publish your Roe site
status: published
tags: deploy, publish, system
related:
  - guide-deploy
  - site-sync
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# How Roe publishes your site

Roe has two publishing concepts, and they do different jobs:

- **Deploy** puts the Roe app itself on a host.
- **Site Sync** publishes your site's content to a host.

**Deploy** is about the application. **Site Sync** is about your website.

You have two ways to put your site online, and each one decides which hosts you can use:

- **Publish a static site** — just HTML, CSS, and JavaScript. Every web host supports this.
- **Deploy the Roe app** — run Roe on a host that supports Ruby on Rails. Many hosts do.

To publish a static site, see [Guide → Publish a static site](/documentation/roe/guide-publish).

## When to use a static site vs. deploy the Roe app

A static site has no server. That is its main advantage: because the browser never waits on a server to assemble a page, static sites load fast. Everything the page needs is already there as HTML, CSS, and JavaScript.

Almost every web host offers static hosting, often at low cost.

The trade-off is that server-backed features don't run on a static site. **Members**, **Payments** and **Newsletters** need a server, so they won't work. The **Store** feature and **Snipcart** don't need a server, so they will work.

**Site Sync** connects to your host and pushes your static site files. After the first push, it uploads only the files that changed since your last sync, so you never re-upload the whole site to publish a small edit. You can also download your whole site as a ZIP and upload it yourself.

Use a static site when:

- you're running a content-only website
- you're running a content site with a store
- hosting cost matters

If you want Members, paid content, Payments, or Newsletters, deploy the Roe app instead.

## When to deploy Roe as an app

Deploying the app unlocks Members, paid content, Payments, and Newsletters. It also lets you sign in to Roe from anywhere — your site is no longer tied to your own computer, so you can edit it from any device.

When you run Roe both locally and on a host, **Site Sync** keeps the two copies aligned. It will:

- tell you when one side has changes the other doesn't
- give you a simple way to sync those changes so live and local match
- back up an encrypted copy of your live (production) database to your local machine

Deploy the Roe app when:

- you need the Members, Newsletter, or Payments features
- you want to sign in to your live site and make edits

To deploy the app, see [Guide → Deploy Roe](/documentation/roe/guide-deploy).

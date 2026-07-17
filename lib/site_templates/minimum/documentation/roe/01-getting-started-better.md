---
title: Getting Started with Roe
status: draft
tags: guide, getting-started
url_name: getting-started-better
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Getting started with Roe

#### Before you begin

[Install Roe](/documentation/guide-installation) if you haven't already.

## Roe builds a website from plain files

Roe turns three kinds of files into a website:

- **Markdown** holds your writing. It formats text with ordinary characters like `#` for a heading and `*` for emphasis.
- **Media** holds your images and audio.
- **YAML** holds your settings, one `key: value` line at a time.

You never touch CSS to get a working site. You can edit it later, whenever you want more control.

If Markdown is new to you, keep a [cheat sheet](https://www.markdowntools.io/cheat-sheet) nearby. Mostly, though, you'll pick it up by editing a Post with the preview open, which is the fastest way to learn Roe.

## Watch Roe work: edit a Post with the preview open

The quickest way to understand Roe is to see it respond as you type:

1. Open the [Admin](/admin) and click **Posts**.
2. Create a new Post.
3. Click **Preview** to open a live preview in a new tab.
4. Put the preview on one side of your screen and the editor on the other.
5. Save the Post. The preview refreshes, so each change appears the moment you make it.

Now edit the Post and save again. Each save shows you exactly how Roe reads your Markdown. When you're ready to go further, try the toolbar buttons in [The Editor](/documentation/the-editor).

## Where to edit each part of your site

Every Roe site has three parts, and you edit each one in the Admin:

- **Header and navigation** — [Admin → Layouts](/admin/layouts)
- **Your content** — Pages, Posts, and Products:
  - Posts — [Admin → Posts](/admin/posts)
  - Pages — [Admin → Pages](/admin/pages)
  - Products — [Admin → Products](/admin/products) (enable the [Store](/documentation/store) first)
- **Footer** — [Admin → Layouts](/admin/layouts)

## Build pages from blocks, not a templating language

Most site builders make you learn a templating language. Roe doesn't. Instead it gives you [Roe-anji](/documentation/roeanji): small Markdown extensions that add features like Collections, Cards, and Galleries. You combine these simple blocks to build complex pages.

### Collections show a list of your content

A Collection gathers your content into a list — your latest Posts, featured Products, or related articles — and you can drop one almost anywhere. It works like a blog feed, except you choose what it shows and where it appears. [Learn more about Collections →](/documentation/collections)

Collections most often live on Pages, such as a Blog page or a Podcast page, but they fit elsewhere too:

- In a Post — say, three related Posts at the end of an article.
- On a Product page — say, three related Products beneath each one.

### Cards drop a styled block into your text

A Card places a styled element straight into your Markdown — a pullquote, a post link, a product link, or an aside. [Learn more about Cards →](cards.md)

### Galleries turn a few lines into an image grid

A Gallery arranges images into a grid from a few lines of Markdown. [Learn more about Galleries →](/documentation/galleries)

## What you can build with Roe

One Roe site can run a full blog and newsletter, an online store, paid memberships, and a podcast. It sends email through Postmark, handles the shop through Snipcart, and takes payments through Stripe.

Together, these features replace about five separate paid services — for less money, on a site you own.

Have a question or an idea? Reach out with [issues](mailto:roe@weareontheweb.com?subject=Roe%20bugs), [feedback](mailto:roe@weareontheweb.com?subject=Roe%20feedback), [feature requests](mailto:roe@weareontheweb.com?subject=Roe%20requests), or just to say [hello](mailto:roe@weareontheweb.com?subject=Just%20saying%20hello).

---
title: Getting Started with Roe
status: published
tags: guide
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Getting started with Roe

#### Before Roe

[Install Roe](/documentation/guide-installation) if you haven't. I have a feeling this is going to be an important step.

## First Steps

- Visit the [Admin](/admin) and click Posts in the navigation
- Create a new Post
- Click `Preview` to open up a live preview of the Post in a new tab.
- Put the Preview tab/window on one side of your screen and the Post on the other
- As you save the Post, the Preview will auto-refresh so you can see your changes as you make them.

This is a great way to learn how things work as you can see the changes live. Try out the buttons in [The Editor](/documentation/the-editor).

## What is Roe

Roe helps you build a website with nothing but [Markdown](/documentation/glossary#markdown) files, media and [YAML](/documentation/glossary#yaml). You can dive deeper and edit the CSS if you please but this is not required to build a full/working website with Roe. An understanding of [Markdown Syntax](https://www.markdowntools.io/cheat-sheet) will be helpful but you'll be able to figure out what's going on by working on a Post with a Preview open as suggested [above](#first-steps).

## Important things to know

### Structure of your site

Since Roe is built on Markdown files, the basic structure of your site will be:

- **Header/Navigation**
  - Edit the Navigation in Admin > [Layouts](/admin/layouts)
- **Page/Post Content**
  - Create/edit Posts in Admin > [Posts](/admin/posts)
  - Create/edit Pages in Admin > [Posts](/admin/pages)
  - Create/edit Products in Admin > [Posts](/admin/products)
    - <mark>(you must enable the</mark> [Store](/documentation/store) <mark>first)</mark>
- **Footer**
  - Edit the Navigation and Footer in Admin > [Layouts](/admin/layouts)
  
## Unique features of Roe

Roe was built with the idea of taking simple/modular building blocks and combining them to create more complex sites. For this reason Roe does not use a templating language. Instead it uses [Roe-anji](/documentation/roeanji), simple markdown exentions and syntax that allow you to do all kinds of cool things: Collections, Cards, Galleries, and more.

### Roe-anji - Collections

A Collection in Roe is similar to a blog feed in other systems but it's much more flexible. Most often, it's a list of Posts but it could be a list of Pages, Documentation, Products. In Roe, you can add them anywhere using a simple syntax. And you can customize them to create any kind of content Collection you want. [Learn more about Collections →](/documentation/collections)

Collections are generally added to Pages since they're often collections of Posts and Products but you could:

- put a Collection into a Post as well. Perhaps 3 related Posts or 3 featured Posts at the bottom of an article.
- put a Collection into a Product page, perahps 3 related Products at the bottom of each one.

### Roeajni - Cards

Cards allow you to embed styled elements directly in a Markdown file: pullquote, post link, aside. [Learn more about Cards →](cards.md)

### Roe-anji - Image Galleries

Galleries allow you to create complex grids of images with very simple syntax. [Learn more about Galleries →](/documentation/galleries)

## Onwards… What could you build with Roe?

Roe supports a full newsletter system, store and memberships with payments through 3 integrations: Postmark, Snipcart and Stripe. It also has a full podcast system, no other hosting required.

If you wanted to, you could replace about 5 other paid services with Roe, save a ton of money and have more fun running your site.

Please reach out with any [issues](mailto:roe@weareontheweb.com?subject=Roe%20bugs), [feedback](mailto:roe@weareontheweb.com?subject=Roe%20feedback), [feature requests](mailto:roe@weareontheweb.com?subject=Roe%20requests) or just to say [hello](mailto:roe@weareontheweb.com?subject=Just%20saying%20hello).

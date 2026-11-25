---
title: "Dashboard"
status: published
tags: admin
---

# Roe Dashboard

The dashboard has several useful sections:

1. [Content](#content)
2. [Links](#links)
3. [System](#system)
4. [Payments](#payments)
5. [Orders](#orders)

## Content

This section gives you a count of all your pages, posts, episodes, tracks and products. It will show you a count of `published`, `draft`, and `unlisted` for each content type.

Published, Unlisted, Drafts or Total are links to those items in Roe. Clicking [Published](/admin/posts?status=published&type=article) on Articles will bring you to the Posts section, showing only `published`, `article` posts. It's the same for all the content sections.

==Note:== episodes, tracks and products only appear if Podcasts, Music and Store are enabled features.

## Links

The Links section covers any issues with internal or media links in your site. It will show you totals for:

- Missing media
- Broken links
- Links to drafts
- Total (all internal and media links in your site)

You can click `VIEW LINKS →` for details on all the broken links in your site. Roe will update  this page when Roe starts up, after you save any content, after an upload, after rename and when you click `[ CHECK NOW ]`.

The `live` and `local` sites both check their own links. Links to external sites and sources are skipped.

### Links Page

This page has 4 sections:

1. Media (issues with links to your media)
2. Links (issues with internal links)
3. Links to Drafts (lists links to any `draft`)
4. In Drafts (lists broken links inside any `draft`)

Click on an item and it will open The Editor with the broken link or media path selected so you can fix the issue.

The first 2 sections are important as they show you any broken links or media for your public content. The Drafts sections let you know if a link is pointing to a draft or if there are links within drafts. 

Any link to a `draft` will show as plain text until the content becomes published. This allows you to add links to drafts without adding broken links to your site.

## System

This tells you the size of your backups and database as well as how many backups you have.

## Payments

This section will only show up if you've enabled Memberships and Payments for your site and Stripe has been configured. You can do this on your [Roe: Settings](/admin/configs) page. This is a simple log of payments you've received through Roe. It includes membership upgrades and donations.

## Orders

This section will only show up if you've enabled the Store and are using Snipcart for your site. You can do this on your [Roe: Settings](/admin/configs) page. This is a log of orders made through Roe. You can click through to `VIEW ORDERS →` to see details on those orders.

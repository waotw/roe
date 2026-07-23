---
title: "Settings → Site"
status: published
tags: settings
---

# Edit your Global Site Settings

Your Global Site Settings cover the basics of your whole site — its name, branding, theme, and more. Edit them in the Admin at [Settings → Site](/admin/configs/site/edit). Click `SAVE` when you're done.

## Site Information

- `Site Title` (required) — your site's name. Shown in page titles, feeds, and the header.
- `Site URL` (required) — your site's full web address, like `https://example.com`. Used in emails and feeds.
- `Site Description` — a short description of your site. Used in meta tags and RSS/Atom feeds.
- `Author Name` — the default author for your posts and pages.
- `Author Email` — a contact address for the site author.

## Branding

- `Logo Image Path` — an image to show in your header instead of text. Copy its URL from `GLOBAL IMAGES`.
- `Logo Style` — how the logo appears: `beside_text` (logo next to your title) or `replace_text` (logo instead of the title). Appears once you set a logo, and can be styled further in your theme's CSS.
- `Favicon` — the small icon browsers show in the tab. Copy its URL from `GLOBAL IMAGES`.
- `Social Image` — the image shown when your site is shared on Facebook, X, LinkedIn, iMessage, or Slack. Use 1200×630 for best results.
- `Always use Social Image` — use the image above on every page and post when your site is shared on social media, even a page or post has it's own image. This does not affect how the images are shown on your site, only when shared on social media. Appears once you set a social image.
- `Social Image Alt Text` — describes the social image for screen readers and card previews. Skip it when your posts and pages set their own.
- `Twitter / X handle` — your handle, for the "via @you" credit on shared cards. The leading `@` is optional.

## Theme

- `Active Theme` — the theme your site uses. You can also switch themes on the [Themes](/admin/themes) page, which updates this setting for you.

## Site Sync

- `Transport` — how Site Sync moves files to and from your live site: `http` (recommended; works over HTTPS with a shared token) or `rsync` (needs SSH access to the host).

## Updates

- `Nightly updates` — receive pre-release (nightly) versions instead of stable releases. Off means stable.

## Static Site Generation ([SSG](/documentation/roe/glossary#ssg))

- `Enable Auto-Generation` — keep a static (plain-file) copy of your site up to date and serve it to your visitors.
- `STATIC SITE ACTIONS` — This button takes you to a page with various actions to help with SSG troubleshooting

When this is on, Roe does two things: it rebuilds the static copy of your site whenever your content changes, and it serves that copy to visitors instead of the running app. This applies whether you run Roe locally or deploy it — Roe is still running, but what visitors see is the static version.

Because visitors are served plain files, anything that needs the running app — Members, Payments, and other database-backed features — won't work while this is on.

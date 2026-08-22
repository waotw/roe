---
title: Settings → Cards
status: published
url_name: settings-cards
tags: settings
related:
  - cards
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Cards: Default Settings

These settings decide what a card does by default. If the card itself specifies something, the card will win. Set the defaults here and all cards will work that way unless you change a specific card.

Leave an option off a card and it follows the setting you've set in [Settings → cards.yml](/admin/configs/cards/edit)

## Post-link

- `default_style` — `small`, `medium` or `large`. The post-link size. This adds a CSS class to the post-link which can be styled in CSS.
- `default_image` — used when a post has no image of its own.
- `default_link_text` — the wording for the link to the post.
- `default_show_subtitle` — whether post-links show the subtitle. Leave it blank and the style decides: off for `small`, on for `medium` and `large`.
- `default_show_excerpt` — the same, for the excerpt. Blank means the style decides, which is on for `large` only.

## Pullquote

- `default_position` — `left`, `right` or `center`.

## Product-link

- `default_link_text` — the wording of the link on a product card. Defaults to `View product →`.

## Aside

Nothing to set. An aside's text is Markdown, so write links directly in the `text:` of the aside. See [Aside options](/documentation/roe/cards#aside).

## How the card builder uses default settings

`CARD ▼` in the editor opens the card builder, and each field starts on the setting above. Change what you want and click Insert.

The builder inserts the card with the options you choose. You might notice that if you leave an option as the default, that option isn't written into the card when you insert it. This is deliberate. This allows you to update all the cards from the global settings rather than having to update every card one-by-one if you decide you want to change them.

If you want a card to always have specific options, add them to the card itself and that will override the global settings.

See all available options for:

- [Aside options](/documentation/roe/cards#aside)
- [Pullquote options](/documentation/roe/cards#pull-quote)
- [Post-link options](/documentation/roe/cards#post-link)
- [Product-link options](/documentation/roe/cards#product-link)

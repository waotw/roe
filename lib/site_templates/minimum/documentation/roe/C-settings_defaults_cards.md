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

# Cards: Default Settings & Template

This allows you to customize the defaults used in Cards, as well as the Buttons which generate the code in the Editor.

### Post-link
- `default_image` - if a post doesn't have an image but the post link requires it, this is the image that will show up.
- `default_style` - `small`, `medium` and `large` - each of these will create a CSS class that you can use to style them.
- `default_link-text` - if you add `link_text:` to the card that will take precedent but if not, this will be used.

### Aside
- `default_link-text` - if you add `link_text:` to the card that will take precedent but if not, this will be used.

### Pullquote
- `default_position` - `left`, `right`, `center`

### The `CARD ▼` button in the editor

This button drops a `card` template into your Markdown. This is where those templates live.

See all available options for:

- [Aside options](/documentation/roe/cards#aside)
- [Pullquote options](/documentation/roe/cards#pull-quote)
- [Post-link options](/documentation/roe/cards#post-link)

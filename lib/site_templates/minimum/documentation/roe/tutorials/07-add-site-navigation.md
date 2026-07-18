---
title: 7) How to add navigation
status: published
tags: tutorial
related:
  - 8-how-to-edit-your-site-settings
---

#### Previous Tutorial
```collection
source: documentation/roe
related: true
limit: 1
offset: 1
template: links
```

# How to add Navigation to your site

1. Open Roe's [Admin](/admin)
2. Select Layout
3. Click `Edit` for Navigation
4. Replace `Your site` inside `[Your site](/)` with your site name.
5. Note this Collection with `template: menu`. Learn about this Collection template here: [When to use the `menu` template](/documentation/roe/collections_templates#when-to-use-the-menu-template)
6. Click `PREVIEW`
7. You should see both `home` and the page you just created with `collection: nav` in the metadata.

You can add more links to this Collection in two ways:

- Add their `url_name` to the `order`. Click `SHOW LINKS` in the layout editor to see the `url_name`s for all your pages.
- Add `nav` as a `collection` in any page's metadata. You did this in the last tutorial for the page you created — it "sends" the page to the `nav` Collection.

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

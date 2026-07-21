---
title: Snipcart
status: published
url_name: snipcart
tags: integration
related:
  - store
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

#### Before Snipcart

Snipcart needs the Store feature. Enable it in [Admin → Settings](/admin/configs) by clicking `ENABLE STORE` — `store.yml` then appears in the `Features` section.

# Setting up Snipcart to work with Roe

The Store feature lets you sell products directly from your site using [Snipcart ↗](https://snipcart.com). Three pieces have to be in place for Roe and Snipcart to work together:

1. Roe needs Snipcart's `<script>` — covered in this article.
2. Your Store settings need to be configured — see [Store](/documentation/roe/store).
3. You need at least one product — see [Products](/documentation/roe/products).

## The Snipcart side

Snipcart walks you through creating an account when you sign up. This article covers only the piece Roe needs from it.

Snipcart has a [Test mode and a Live mode ↗](https://docs.snipcart.com/v3/testing/environment), and Roe has the same two modes:

- **Test** — fake payments, for setting things up and checking everything works.
- **Live** — real payments, for when you're ready to sell.

In Roe, each mode's snippet lives on its own tab — **Local/Test** and **Live/Static Site** — and the Active Mode toggle picks which one is active. In either mode, Roe needs just one thing from Snipcart: its `<script>` snippet.

To add it:

1. Open Snipcart's [API Keys ↗](https://app.snipcart.com/dashboard/account/credentials) page. The label at the top — **Public Test** or **Public Live** — tells you which mode you're using in Snipcart.
2. Copy the `<script>` snippet in full.
3. In Roe, open [Settings → Roe → Store (Snipcart)](/admin/configs/snipcart/edit).
4. Paste it into the matching tab: **Local/Test** or **Live/Static Site**.
5. Click **Save Test Snippet** (or **Save Live Snippet**).

That's it — you're ready to work with the Store and Snipcart.

### Domains and going live

When you make the store public, the domain in your Snipcart dashboard must match your store's domain — otherwise Snipcart rejects orders.

- [Snipcart: Domains & URLs ↗](https://docs.snipcart.com/v3/dashboard/domains-urls)
- [Roe: Store](/documentation/roe/store)

---

That covers the Snipcart settings. To finish setting up your store, see [Store](/documentation/roe/store) and [Products](/documentation/roe/products).

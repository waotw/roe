---
title: Snipcart
status: published
url_name: snipcart
tags: integration
related:
  - store
  - products
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

Snipcart walks you through setting up an account when you sign up in the "Get started with Snipcart" steps. Go through each step in that list and you'll be ready to test and process real payments.

This article covers only the pieces Roe needs from Snipcart.

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

## Digital goods

A digital good is a file Snipcart delivers after payment — an album, a PDF, a sample pack. You upload the file to Snipcart, and connect it to the product in Roe.

Snipcart identifies each uploaded file by a **GUID**, a long identifier that looks like this:

```
7235bd18-1745-488e-bdbb-dc4f424c1ca1
```

A GUID is the only link between your product in Roe and the file in Snipcart, and you copy it into Roe.

### Selling a file

1. Open Snipcart's [Digital Goods ↗](https://app.snipcart.com/dashboard/digital) page and drag your file into the drop zone.
   Snipcart uploads it and shows you a `GUID`.
2. Copy the `GUID`.
3. In Roe, open or create a Product for this file — see [Products](/documentation/roe/products).
4. In the product's metadata, check the `digital` toggle let Roe know this is a digital good.
   A `file_guid` field appears below it.
5. Paste the GUID into `file_guid`.
6. Save.

The `file_guid` field has a link straight back to Snipcart's Digital Goods page so you can copy/paste it in Roe. Roe warns you in the editor if the GUID is missing or malformed. If `digital` is checked and the `file_guid` has issues, the `ADD TO CART` button won't render. This is to prevent a user from paying for something that won't be delivered.

### What you set in Snipcart, not Roe

Two things about the download live on Snipcart's side, on the same [Digital Goods ↗](https://app.snipcart.com/dashboard/digital) page where you uploaded the file:

- **Access expiry** — how many days the download link keeps working.
- **Download limit** — how many times a buyer can download the file.

See [Snipcart: Store management ↗](https://docs.snipcart.com/v3/dashboard/store-management) for more info.

### Selling several files as variants in a Product Group

Each variant is its own product with its own SKU, so each one carries its own `file_guid`. A release sold as MP3 and FLAC is two products in a group, each pointed at a different upload. See [Product variants & groups](/documentation/roe/products#product-variants-groups).

### Turning it off

Setting `digital` back to `false` hides the GUID field and Roe will no longer send it to Snipcart. The product goes back to being physical and shipped, and the cart asks for an address again. The GUID stays in the file in case you switch back, but it does nothing while the toggle is off.

---

That covers the Snipcart settings. To finish setting up your store, see [Store](/documentation/roe/store) and [Products](/documentation/roe/products).

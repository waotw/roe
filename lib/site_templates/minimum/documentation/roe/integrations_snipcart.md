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

# Setting up Snipcart to work with Roe

The Store feature lets you sell products directly from your site using [Snipcart](https://snipcart.com). There are 3 key pieces that must be in place for Snipcart & Roe to work together:

1. Roe needs the API Keys from Snipcart (covered in this article)
2. Your Store settings need to be set up (covered here: [Store](/documentation/store))
3. You need at least one product (covered here: [Products](/documentation/products))

#### Before Snipcart

You'll need to enable the Store feature, go to: [Admin → Settings](/admin/configs) and click `ENABLE STORE`. You will see see `store.yml` in the `Features` section.

## Snipcart settings

When you sign up for Snipcart, it has excellent onboarding that leads you through setup. You can configure things how you like. This article will cover the required settings in Snipcart to get a store working in Roe.

Whether in Test or Live Mode, there are 2 things you'll need from Snipcart:

1. Snipcart's `<script>`
2. Secret API Key (which you create)
    - a TEST mode secret key starts with `ST_`
    - a LIVE mode secret key starts with `S_`

<mark>Note: NEVER paste a Live Mode Secret into the Test Mode on Roe. Test API keys are saved locally in plain text.</mark>

These are all available on the [API Keys](https://app.snipcart.com/dashboard/account/credentials) page (whichever mode you're in):

1. Go to: [https://app.snipcart.com/dashboard/account/credentials](https://app.snipcart.com/dashboard/account/credentials)
2. Copy the `<script>` snippet in it's entirety.
3. Create a Secret API Key if you haven't already.
4. Copy that Key.
5. Come back to Roe: [Admin → Settings → snipcart.yml](/admin/configs/snipcart/edit)
6. Paste the Snippet in it's section, paste the Secret Key in it's section.
7. Click `SAVE (TEST/LIVE KEYS)`.

If all seems well, the indicator at the top of the page will be green and say `Connected`.

### Domains & Going Live

When it's time to make the store public, it's important that the domain set on Snipcart and the domain for your Store match:

- [Snipcart: Domains & Urls](https://docs.snipcart.com/v3/dashboard/domains-urls)
- [Roe: Store](/documentation/store)

---

That's it for the Snipcart settings. Check these aritcles for further setup: [Store](/documentation/store), [Products](http://localhost:3000/documentation/products)

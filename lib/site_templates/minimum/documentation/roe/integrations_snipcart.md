---
title: Integrations → Snipcart
status: published
url_name: snipcart
related:
  - "store"
---

##### Related documentation

```collection
source: documentation
related: true
limit: all
template: links
```

# Setting up Snipcart to work with Roe

The Store feature lets you sell products directly from your site using [Snipcart](https://snipcart.com). Products are markdown files similar to pages/posts with metadata for price, SKU, images, etc.

#### Before Snipcart

You'll need to enable the Store feature, go to: [Admin → Settings](/admin/configs) and click `ENABLE STORE`. You can then edit the store settings under: Features → `store.yml`.

## Snipcart settings

Whether is Test or Live Mode, there are 2 things you'll need to set up Snipcart with Roe. These are both available on the API Keys page (whichever mode you're in):

<mark>Note: Never paste a Live Mode Secrets into the Test Mode on Roe. Test API keys are saved locally in plain text.</mark>

1. Go to: [https://app.snipcart.com/dashboard/account/credentials](https://app.snipcart.com/dashboard/account/credentials)
2. Copy the `<script>` snippet in it's entirety.
3. Create a Secret API Key if you haven't already.
4. Copy that Key.
5. Come back to Roe: [Admin → Settings → snipcart.yml](/admin/configs/snipcart/edit)
6. Paste the Snippet in it's section, paste the Secret Key in it's section.
7. Click `SAVE (TEST/LIVE KEYS)`.

If all is well, the indicator at the top of the page will be green and say `Connected`.

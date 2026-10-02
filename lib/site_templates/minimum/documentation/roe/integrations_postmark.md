---
title: Postmark
status: published
url_name: postmark
tags: integration
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Setting up Postmark to work with Roe

Postmark is how Roe sends email. That covers two different things:

- **Sign-in links and confirmations**, required by the Members feature in Roe. Members sign in with their email address.
- **Newsletters**, if you turn them on.

#### Before Postmark

1. You'll need to enable the Members feature, go to: [Settings](/admin/configs) and click `ENABLE MEMBERS`. Postmark appears in your settings as soon as Members is on — you don't need Newsletters for it. Turn Newsletters on separately if you want to send posts to your list.
2. You'll want to make sure that you've added Author Email to: [Settings → site.yml](/admin/configs/site/edit). This is the email address that will be used by Postmark.

## 1. Setting up your Postmark account

Postmark has good documentation. Use this article to get your account set up correctly: [Getting started with Postmark](https://postmarkapp.com/support/article/1002-getting-started-with-postmark). This is **very important**, as it ensures that your emails are delivered.

Here is a helpful video from Postmark: [Getting Started With Postmark in 5 Steps](https://postmarkapp.com/videos/getting-started-with-postmark-in-5-steps)

### On Postmark

1. Go to Postmark and sign into your account
2. Go to [Account → API Tokens](https://account.postmarkapp.com/account/api_tokens)
3. Copy your Account API Token
    - You'll need to paste this into Roe's settings.

## 2. Connect Postmark to Roe

1. Go to: [Settings → postmark.yml](/admin/configs/newsletters/edit)
2. Under **Postmark Setup**, paste your Account API Token
3. Click `SET UP POSTMARK INTEGRATION`
4. Choose to have Roe create new servers or select existing servers
5. Click `CONFIRM & CONNECT`
    -  Roe will create or reuse your servers, then create the [webhooks](/documentation/roe/glossary#webhook) automatically.
6. You'll see a full list of checks under **Integration Status**
    - If there are any issues, you will be directed to fix them on Roe or Postmark as needed.

When everything has a green ✓, you're all set.

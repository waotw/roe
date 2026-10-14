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

Members can sign up with just their name and email.

#### Before Postmark

1. You'll need to enable the Members feature, go to: [Settings](/admin/configs) and click `ENABLE MEMBERS`. Postmark appears in your settings as soon as Members is on — you don't need Newsletters for it. Turn Newsletters on separately if you want to send posts to your list.
2. You'll want to make sure that you've added Author Email to: [Settings → site.yml](/admin/configs/site/edit). This is the email address that will be used by Postmark.

## 1. Basic Postmark Setup

Postmark has good documentation. Use this article to get your account set up correctly: [Getting started with Postmark](https://postmarkapp.com/support/article/1002-getting-started-with-postmark). This ensures that your emails are delivered reliably. On Postmark, make sure to verify the Author Email you've set in Roe: [Settings → site.yml](/admin/configs/site/edit)

1. Create a new Server or use the defaults created with your account (you can rename them)
    - [Servers FAQ](https://postmarkapp.com/support/article/1137-servers-faq)
    - [Message Streams Video](https://postmarkapp.com/videos/message-streams) (if curious)
2. Postmark 
2. Go to [Servers](https://account.postmarkapp.com/servers) → Open your server → API Tokens
3. Click the token to copy it
    - You'll need to paste this into Roe's settings.

### 2. Connect Postmark to Roe

1. Go to: [Settings → postmark.yml](/admin/configs/newsletters/edit)
2. Paste your Server API Token
3. Click **"Save Configuration"**
4. You'll see a green confirmation if successful

### 3. Configure Webhooks

Webhooks tell Roe when emails are delivered, bounce, or are marked as spam. We recommend testing webhooks on a live URL/server.

1. In Postmark, go to Postmark Server → Choose your Broadcast Stream → Settings → Webhooks
2. Click **"Add webhook"**
3. Copy the webhook URL shown in Roe's Postmark settings
4. Paste it into Postmark: `Webhook URL`
5. Enable these events:
   - ✅ **Delivery** (optional, for logging)
   - ✅ **Bounce** (required)
      - ✅ include message content
   - ✅ **Spam Complaint** (required)
      - ✅ include message content
6. Click `Send Test` to make sure things are set up correctly
6. Save the webhook
7. You only need to do this for Broadcast Stream.

If all seems well, the indicator at the top of the page will be green and say `Connected`.

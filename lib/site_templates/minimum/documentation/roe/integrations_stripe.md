---
title: Stripe
status: published
url_name: stripe
tags: integration
related:
  - "payments"
---

##### Related documentation

```collection
source: documentation
related: true
limit: all
template: links
```

# Setting up Stripe to work with Roe

Stripe has a Sandboxes which allows you to test everything before you make things public. For this reason there are 2 modes in Roe: Test and Live. Here is an article about [Sandboxes on Stripe](https://docs.stripe.com/sandboxes#manage-sandboxes-in-the-dashboard)

Stripe has an excellent onboarding that helps you set up what you need to accept payments. This article assumes you've created and account and gone through basic Stripe setup.  
[Getting started wtih Stripe](https://support.stripe.com/topics/getting-started)

#### Before Stripe

You'll need to enable the Members feature, go to: [Admin → Settings](/admin/configs) and click `ENABLE MEMBERS`. You will then set up Members and there you can enable `Payments` which turns on Stripe in Roe.

## 1. Get Your Stripe API Keys

1. Go to [Stripe.com](https://stripe.com/) and sign into your account, this will bring you to your Dashboard.
2. On the very bottom left, you'll see `Developers`. Click that, followed by `API Keys`.
3. From **Standard keys**: Copy your **Publishable Key** and **Secret Key**.
    - If you're in Sandbox/Test mode, the keys will start with: `pk_test_` and `sk_test_`
    - If you're in Live mode, the keys start with: `pk_live_` and `sk_live_`
4. *Optional but recommended* - [Limit an API key to certain IP addresses](https://docs.stripe.com/keys#limit-api-secret-keys-ip-address) - Especially for live keys.

## 2. Add Keys to Roe

1. Go to [Admin → Payments](/admin/configs/payments/edit)
2. Choose your mode: Test/Live
3. Paste your Publishable Key
4. Paste your Secret Key
5. Click `SAVE (TEST/LIVE) KEYS`

If successful, you'll see: `Connected Mode: Test/Live` near the top of the page. You can now start accepting real or test payments.

## 3. Set Up Webhooks

Webhooks allow Stripe to tell Roe when a payment is successful, fails, or a refund is requested/processed.

### On Stripe.com

In your Stripe dashboard, go to **Developers (bottom left of window) → Webhooks**:

1. Click `Add destination`
2. Select: `Your account` for **Event destination scope**
3. Search for and check these 4 events: `checkout.session.completed`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.closed`
4. Click `Continue →` and choose: `Webhook endpoint`
5. You'll need the Enpoint URL from Roe ↓

**Open Roe [Admin → Settings → Payments](/admin/configs/payments/edit) in a new tab:**

1. Copy your **Webhook Endpoint** URL for Test or Live (whichever you're setting up)
2. Go back to Stripe, and paste the Endpoint URL `https://yoursite.com/webhooks/stripe`
3. Click `Create destination`
4. Once you create the destination, click the closed eye icon, and copy the Signing secret from Stripe: `whsec_…`
5. Go back to Roe: [Admin → Settings → Payments](/admin/configs/payments/edit) and paste the Signing secret in Roe: `Webhook Signing Secret`.
6. Click `SAVE TEST/LIVE KEYS`

If all seems well, the indicator at the top of the page will be green and say `Connected`.

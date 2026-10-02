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
source: documentation/roe
related: true
limit: all
template: links
```

# Setting up Stripe to work with Roe

Stripe has Sandboxes which allows you to test everything before you process real payments. For this reason there are 2 modes in Roe: Test and Live. Here is an article about [Sandboxes on Stripe](https://docs.stripe.com/sandboxes#manage-sandboxes-in-the-dashboard)

Stripe has an excellent onboarding that helps you set up what you need to accept payments. This help article assumes you've created an account and gone through basic Stripe setup. 
[Getting started wtih Stripe](https://support.stripe.com/topics/getting-started)

#### Before Stripe

You'll need to enable the Members feature, go to: [Admin → Settings](/admin/configs) and click `ENABLE MEMBERS`. You will then set up Members and there you can enable `Payments` which turns on Stripe in Roe.

<mark>Note:</mark> Stripe can only be setup on the live/deployed site at this time.

## 1. Create a Restricted API Key on Stripe

Go to your [Stripe settings](/admin/configs/payments/edit) page in Roe and you'll find the instructions for creating your restricted API key. Follow those instructions to create your key on Stripe.

## 2. Add Keys to Roe

Once you've created the key, come back to your Stripe settings in Roe:

1. Select the tab for the mode you want: Test or Live
2. Paste your Restricted API Key
3. Click `SAVE TEST KEYS` (test mode) or `SAVE LIVE KEYS` (live mode)
4. You'll see a full list of checks under **Integration Status**
  - If there are any issues, you will be directed to fix them on Roe or Stripe as needed.

Roe will set up the webhooks for your site. 

### Update mode

At the top of the settings page, choose the mode you want to use and click `UPDATE MODE`.

When everything has a green ✓, you're all set.

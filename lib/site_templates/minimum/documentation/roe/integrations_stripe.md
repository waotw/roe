---
title: Integrations → Stripe
status: published
url_name: stripe
related:
  - "payments"
---

# Setting up Stripe to work with Roe

To accept payments, you need to connect your Stripe account:

## 1. Get Your Stripe Keys

1. Create a Stripe account at [stripe.com](https://stripe.com)
2. Go to **Developers → API Keys** in your Stripe dashboard
3. Copy your **Publishable Key** and **Secret Key**
4. For testing, use the test mode keys
5. For production, use the live mode keys

## 2. Add Keys to Roe

1. Go to <mark>Admin → Payments</mark>
2. Paste your Publishable Key
3. Paste your Secret Key
4. Click **"Save & Test Connection"**

If successful, you'll see a green confirmation message.

## 3. Set Your Price

1. Go to <mark>Admin → Settings → members.yml</mark>
2. Find the `payments:` section
3. Set `enabled: true`
4. Set your `price:` (e.g., `49.00` for $49)  
  • <mark>Note: Stripe will default to your local currency if set in Stripe</mark>
5. Click **"Save Configuration"**

When you save, Roe automatically creates a product and price in your Stripe account.

## 4. Set Up Webhooks

Webhooks tell Roe when a payment succeeds:

1. In your Stripe dashboard, go to **Developers → Webhooks**
2. Click **"Add destination "**
3. Enter your webhook URL: `https://yoursite.com/webhooks/stripe`
4. Select events: `checkout.session.completed`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.closed`
5. Copy the **Signing Secret**
6. Add it to your Stripe configuration in Roe

Test mode and Live mode have separate webhook endpoints — you'll set up one for each when you're ready to go live.

### Related documentation

```collection
source: documentation
related: true
template: links
```

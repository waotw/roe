---
title: Payments
status: published
url_name: payments
tags: feature
related:
  - members
---

#### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Setting up Payments in Roe

#### Global Payment Settings

This document will explain global settings for Members & Payments:  
[Settings → Features → Members](/documentation/roe/settings-members)

## Setting up Stripe

[Integrations → Stripe](/documentation/roe/stripe)

## Payment Models

The system is flexible and supports different business models:

### 1. Free Newsletter Only

- Don't enable payments
- Use signups to build your email list
- All content is free
- Send newsletters to all members

### 2. Paid Membership

- Enable payments
- Mark premium posts with `audience: paid`
- Use paywall forms to show previews
- Only paid members access full content

### 3. Support/Donation Model

- Enable payments
- Don't mark any posts as paid
- All content remains free
- Members pay to support your work
- Edit upgrade page to say "Support" instead of "Unlock Premium"

### 4. Hybrid Model

- Some posts are free (public)
- Some posts are paid-only
- Some posts show previews to everyone
- Maximum flexibility

## The Payment Flow (Memberships)

Here's what happens when someone upgrades to paid:

1. **Member clicks "Upgrade"** (on their account page or the upgrade page)
2. **Redirected to Stripe Checkout** (secure payment form)
3. **Enters payment details** (credit card, Apple Pay, etc.)
4. **Payment processes** and Stripe sends webhook to Roe
5. **Member upgraded automatically** to paid tier
6. **They can now access paid content**

The entire process is handled automatically - no manual intervention needed.

## Donations (One-Time Support Payments)

Donations are a separate flow from paid memberships. Donors don't need an account, no membership tier is granted — they just send money to support your work.

### Enabling Donations

1. Go to <mark>Admin → Settings → members.yml</mark>
2. In the `payments:` section, set `mode: donations` (donations only) or `mode: both` (donations alongside memberships)
3. Set `donation_amounts:` to the preset buttons you want to offer (default: `[5, 10, 20, 50]`)
4. Save

A donate page is auto-generated at `/donate` (in `site/pages/members/donate.md`). You can edit the copy like any other page.

### How the Donation Form Works

The donate page renders a small form with preset amount buttons and a free-form input for a custom amount:

````markdown
```form
for: donate
button-text: Continue to Stripe →
```
````

**On click of a preset button:**

- The amount fills the input (formatted to the currency's natural decimals — `$5.00`, `€5.00`, `¥5`, `BHD 5.000`)
- The button labels are auto-localized using the currency from your Stripe account (USD shows `$5`, EUR shows `€5`, etc.)
- Nothing submits yet — the donor reviews the amount, edits if they want, then clicks the main "Continue to Stripe →" button

**On submit:**

- Roe creates a Stripe Checkout Session for the donation amount
- Donor is redirected to Stripe to complete the payment
- After payment, Roe records a `Donation` row (email, amount, payment intent) for the dashboard

### Donation Limits

- **Minimum:** $2 (200 cents) — Stripe's minimum for most currencies
- **Maximum:** $1,500 (150,000 cents) — anti-abuse cap

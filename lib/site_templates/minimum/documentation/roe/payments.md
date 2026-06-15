---
roe_version: 0.0.26
title: Payments & Stripe
status: published
url_name: payments
---

# Payments

Roe CMS includes a complete payment system that allows you to:

- Accept one-time payments for premium content access (lifetime paid memberships)
- Gate content behind a paywall with preview snippets
- Accept one-time donations from non-members

You can run any combination of these — paid memberships only, donations only, or both. You can even use payments purely for donations/support without gating any content.

Payments require the [Members](/documentation/members) system to be enabled.

## Payment Modes

When payments are enabled, you choose what you want to offer via the `mode` setting in `members.yml`:

- **`memberships`** — Lifetime paid access only. Members upgrade once and unlock paid content forever.
- **`donations`** — One-time support payments only. Donors don't need an account; they just give money.
- **`both`** — Both flows are available simultaneously.

## Setting Up Payments with Stripe

To accept payments, you need to connect your Stripe account:

### 1. Get Your Stripe Keys

1. Create a Stripe account at [stripe.com](https://stripe.com)
2. Go to **Developers → API Keys** in your Stripe dashboard
3. Copy your **Publishable Key** and **Secret Key**
4. For testing, use the test mode keys
5. For production, use the live mode keys

### 2. Add Keys to Roe

1. Go to <mark>Admin → Payments</mark>
2. Paste your Publishable Key
3. Paste your Secret Key
4. Click **"Save & Test Connection"**

If successful, you'll see a green confirmation message.

### 3. Set Your Price

1. Go to <mark>Admin → Settings → members.yml</mark>
2. Find the `payments:` section
3. Set `enabled: true`
4. Set your `price:` (e.g., `49.00` for $49)  
  • <mark>Note: Stripe will default to your local currency if set in Stripe</mark>
5. Click **"Save Configuration"**

When you save, Roe automatically creates a product and price in your Stripe account.

### 4. Set Up Webhooks

Webhooks tell Roe when a payment succeeds:

1. In your Stripe dashboard, go to **Developers → Webhooks**
2. Click **"Add endpoint"**
3. Enter your webhook URL: `https://yoursite.com/webhooks/stripe`
4. Select events: `checkout.session.completed`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.closed`
5. Copy the **Signing Secret**
6. Add it to your Stripe configuration in Roe

Test mode and Live mode have separate webhook endpoints — you'll set up one for each when you're ready to go live.

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

These can be adjusted in `app/models/donation.rb` if needed.

### Anonymous vs. Logged-in Donations

Donors don't need an account. Stripe Checkout collects an email address as part of the payment, which is recorded with the donation.

If a logged-in member happens to donate, the donation is linked to their member record (so you can see who donated even when they have an account).

### Linking to the Donate Page

Once donations are enabled, the donate page link automatically appears in the **Admin → Layouts** "Show Links" panel, so you can add it to your nav, footer, or any page.

## Creating Paywalled Content

To make a post or page premium/paid-only:

### 1. Set the Audience

Add this to your post's frontmatter:

```yaml
---
title: My Premium Article
audience: paid
---
```

### 2. Add a Paywall (Optional)

You can control where the paywall appears in your content using a `paid_content` form block:

````markdown
This is the free preview that everyone can read. It gives them a taste of what's inside...

```form
for: paid_content
text: This is premium content. Upgrade to continue reading.
button-text: Become a paid member
```

Everything below this point is only visible to paid members. This is where your premium content lives - the analysis, insights, and deep dives that paying members get access to.
````

**How it works:**
- ✅ **Paid members** see the entire post (paywall form is hidden)
- ✅ **Free members & guests** see everything up to the form, then content stops
- ✅ **The form** shows an upgrade button linking to `/upgrade`

**In the editor:** When editing a post with `audience: paid`, you'll see a blue `ADD PAYWALL` button in the toolbar. Click it to insert the paywall form block instantly.

### 3. Without a Paywall Form

If you mark a post as `audience: paid` but don't add a paywall form, visitors who try to access it will be redirected to your <mark>Upgrade</mark> page.

## Smart Upgrade Buttons

The upgrade page shows different buttons depending on who's viewing it:

````markdown
```form
for: checkout
member-button-text: Upgrade Now
non-member-button-text: Sign up as paid member
```
````

**How it works:**
- **Signed-in free members** see "Upgrade Now" → goes straight to Stripe
- **Not signed in** see "Sign up as paid member" → goes to signup page
- **Paid members** don't see the form (they're already paid)

This creates a seamless experience - everyone sees the right call-to-action for their situation.

## Configuration Options

Edit these in <mark>Admin → Settings → members.yml</mark>:

### Payments Section

```yaml
payments:
  enabled: true
  mode: both                       # memberships | donations | both
  price: "49.00"
  donation_amounts: [5, 10, 20, 50]
```

**`enabled`** — Turn payments on/off. When `true`, upgrade buttons / donation forms appear based on `mode`.

**`mode`** — Which flow(s) to offer:

- `memberships` — only the paid-membership upgrade flow
- `donations` — only the one-time donation flow
- `both` — both flows are available

**`price`** — Membership price in your Stripe default currency (e.g., `"49.00"` for $49). Only used when `mode` is `memberships` or `both`.

**`donation_amounts`** — Preset donation buttons in your Stripe default currency. Only used when `mode` is `donations` or `both`. Falls back to `[5, 10, 20, 50]` if not set.

For non-payment-related configuration (like `everyone.show_paid_content`), see [Members](/documentation/members).

## Payment Models

The system is flexible and supports different setups:

### Paid Membership

- Enable payments with `mode: memberships`
- Mark premium posts with `audience: paid`
- Use paywall forms to show previews
- Only paid members access full content

### Support / Donation Model

- Enable payments with `mode: donations`
- Don't mark any posts as paid
- All content remains free
- Visitors can chip in any amount via `/donate`
- Edit the donate page copy to match your tone

### Hybrid Model

- Enable payments with `mode: both`
- Some posts are free (public)
- Some posts are paid-only
- Some posts show previews to everyone
- Donations available alongside paid memberships
- Maximum flexibility

## Collections & Paid Content

Collections automatically respect paid content settings:

---

```collection
heading: Latest Posts
limit: 5
```

---

**How it works:**

- ✅ **Paid posts show** in collections (with lock icon if `show_paid_indicator: true`)
- ✅ **Clicking a paid post** shows the paywall/preview or redirects based on `show_paid_content` setting
- ✅ **Paid members** see all posts normally

## Webhooks & Security

Roe communicates with Stripe directly via webhooks.

When a payment succeeds:

1. Roe receives event from Stripe
2. Verifies it's legitimate (using signing secret)
3. Finds the member by ID in metadata (or records a Donation)
4. Upgrades them to paid tier (memberships) or records the donation row (donations)

The system also handles:

- `charge.refunded` — marks the donation/membership as refunded; refunded paid members are auto-downgraded to free
- `charge.dispute.created` / `charge.dispute.closed` — surfaces an "open disputes" banner on the admin dashboard until resolved in Stripe

The webhook handler includes error handling for:

- Missing member IDs
- Deleted members
- Duplicate payments
- Invalid webhooks (signature verification rejects forged requests)

## Static Site Generation

If you're using static site generation:

- **Paywalled content** is properly truncated in generated HTML
- **Payment pages** (upgrade, donate) require server-side processing
- **Webhooks** require a live Rails endpoint
- ⚠︎ **Consider** keeping payment pages dynamic even in static mode

## Use Cases & Examples

### Newsletter with Premium Tier

1. Free signup builds your list
2. Weekly newsletter to all members
3. Premium posts (deep dives, archives) for paid members
4. Use paywalls to show first few paragraphs to everyone

### Paid Community

1. All content behind paywall
2. Single payment for lifetime access
3. No free previews (`show_paid_content: false`)
4. Members-only discussion/comments

### Donation-Supported Blog

1. All content free and public
2. Payment enabled with `mode: donations`
3. Customize donate page: "Buy me a coffee" style
4. Donors get satisfaction of supporting (no membership tier change)

### Course or Ebook Access

1. Landing page is free (public)
2. Course content marked `audience: paid`
3. One-time payment unlocks all lessons
4. Lifetime access to materials

## Troubleshooting

**Payments not working?**

- Check Stripe keys are correct (test vs live mode)
- Verify webhook is set up and receiving events
- Check webhook signing secret matches the mode you're testing in (test vs live have separate secrets)

**Paywall not showing?**

- Confirm `audience: paid` is in frontmatter
- Check if you're logged in as a paid member (paywall hidden for you)
- Verify `show_paid_content: true` in members.yml (or the relevant `everyone.show_paid_content` setting)

**Upgrade button not appearing?**

- Confirm `payments.enabled: true` in members.yml
- Confirm `payments.mode` is `memberships` or `both`
- Check if Stripe is connected
- Verify you have a price set

**Donate page shows "Donations are not enabled"?**

- Confirm `payments.enabled: true`
- Confirm `payments.mode` is `donations` or `both`

**Donate buttons all show as one button containing `[5, 10, 20, 50]`?**

- This means `donation_amounts` was saved as a quoted string instead of a YAML array.
- Open `members.yml` in raw mode and ensure the value is `[5, 10, 20, 50]` without surrounding quotes, then save.

## Next Steps

1. **Connect Stripe** — Add your test mode keys to start
2. **Pick your mode** — `memberships`, `donations`, or `both`
3. **Customize your member pages** — Edit copy on `upgrade.md`, `donate.md`, etc.
4. **Create your first paid post** — Add `audience: paid` and a paywall form (memberships)
5. **Test the full flow** — Use Stripe test cards to walk through checkout end-to-end
6. **Set up webhooks** — Make sure payments / refunds / disputes update Roe automatically
7. **Go live** — Switch to Stripe live keys when ready

The payment system is designed to grow with you — start with test mode, add the flow that fits your model, and switch on live keys when you're confident.

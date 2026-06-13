---
roe_version: 0.0.20
title: Members & Payments
status: published
---

# Members & Payments

Roe CMS includes a complete membership and payment system that allows you to:
- Build an email list with free member signups
- Accept one-time payments for premium content access
- Gate content behind a paywall with preview snippets
- Manage members and their access levels from the admin

The system is designed to be flexible: you can use it for free newsletters only, paid memberships only, or a combination of both. You can even use payments purely for donations/support without gating any content.

## Enabling the Members System

1. Go to <mark>Admin → Settings</mark>
2. Click **"Enable Members"**
3. Choose how you'd like paid content to be presented on the site
4. Finish setup with: **"Enable Members"**

This creates:

- Your members configuration
- Member pages: signup, signin, upgrade, check-email

## Member Pages

When you enable members, Roe generates several pages that you can customize:

- <mark>Sign up</mark> - Where people create free accounts
- <mark>Sign in</mark> - Where members sign in with their email
- <mark>Upgrade</mark> - Where you pitch your paid membership
- <mark>Check your email</mark> - Confirmation page after requesting a magic link

These are regular markdown pages. You can edit the copy, add images, and customize them however you want.

## How Members Sign In (Magic Links)

Roe uses **passwordless authentication** for free members. When someone signs in:

1. They enter their email address
2. They receive an email with a "magic link"
3. They click the link and are automatically signed in
4. The link expires after 24 hours

Paid members can optionally use passwords (generated automatically after payment), but magic links still work for them too.

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
4. Select events: `checkout.session.completed`
5. Copy the **Signing Secret**
6. Add it to your Stripe configuration in Roe

## The Payment Flow

Here's what happens when someone upgrades to paid:

1. **Member clicks "Upgrade"** (on their account page or the upgrade page)
2. **Redirected to Stripe Checkout** (secure payment form)
3. **Enters payment details** (credit card, Apple Pay, etc.)
4. **Payment processes** and Stripe sends webhook to Roe
5. **Member upgraded automatically** to paid tier
6. **They can now access paid content**

The entire process is handled automatically - no manual intervention needed.

## Signup Options: Free vs Paid

Your signup page can offer two buttons:

````markdown
```form
for: signup
button-text: Sign up free
upgrade-button-text: Sign up and become a paid member
```
````

**How it works:**
- **"Sign up free"** → Creates free account, sends magic link
- **"Sign up and become a paid member"** → Creates account AND redirects to Stripe for payment

The upgrade button only appears if payments are enabled in your config.

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

## Account Management

Members can manage their account at `/account`:

- View their membership tier (free or paid)
- View their status (active or cancelled)
- Update their name
- Update their email (requires confirmation)
- See when they joined and when they upgraded

### Email Change Confirmation

When a member changes their email address:

1. New email is saved as "pending"
2. Confirmation email sent to new address
3. Member clicks confirmation link
4. Email is updated
5. Original email stays active until confirmed

This prevents accidental or malicious email changes.

## Admin: Managing Members

Go to **Admin → Members** to:

- **View all members** with search and filtering
- **See member details** (tier, status, join date, upgrade date)
- **Manually upgrade members** (for comps, gifts, etc.)
- **Cancel memberships** (keeps account, revokes access)
- **Delete members** (removes account entirely)
- **Reactivate cancelled members**

### Manual Upgrades

To give someone free paid access:

1. Go to **Admin → Members**
2. Click on the member
3. Click **"Upgrade to Paid Tier"**
4. Enter a password or let Roe generate one
5. Click **"Upgrade"**

This is perfect for:
- Giving free access to friends/family
- Comp subscriptions for reviewers
- Converting existing supporters

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

## Configuration Options

Edit these in <mark>Admin → Settings → members.yml</mark>:

### Non-Members Section

```yaml
non-members:
  show_paid_content: true
  show_paid_indicator: true
```

**`show_paid_content:`**

- If `true`, non-members can see paywalled posts (with truncation).
- If `false`, they won't see paid content on the site at all.

**`show_paid_indicator`** - Shows a small lock icon next to paid post titles/links.

### Payments Section

```yaml
payments:
  enabled: true
  price: "49.00"
```

**`enabled`** - Turn payments on/off. When `true`, upgrade buttons appear on signup forms.

**`price`** - One-time payment amount in your Stripe default currency (e.g., "49.00" for $49).

## Email Templates

Member emails are customizable markdown files in `site/emails/`:

**`magic_link.md:`**

- Sent when someone requests to sign in

**`email_confirmation.md:`**

- Sent when changing email address

You can edit these templates and use variables like:

- `@member_name` - Member's name
- `@site_title` - Your site title
- `@signin_url` - Magic link URL
- `@confirmation_url` - Email confirmation URL

## Collections & Paid Content

Collections automatically respect paid content settings:

---

```collection
heading: Latest Posts
limit: 5
```

---

**How it works:**

- ✅ **Paid posts show** in collections (with lightning bolt if `show_paid_indicator: true`)
- ✅ **Clicking a paid post** shows the paywall/preview or redirects based on `show_paid_content` setting
- ✅ **Paid members** see all posts normally

## Webhooks & Security

Roe handles Stripe communicates with Stripe directly. 

When a payment succeeds:

1. Roe receives event from Stripe
2. Verifies it's legitimate (using signing secret)
3. Finds the member by ID in metadata
4. Upgrades them to paid tier

The system includes error handling for:

- Missing member IDs
- Deleted members
- Duplicate payments
- Invalid webhooks

## Static Site Generation

If you're using static site generation, member features work differently:

- **Paywalled content** is properly truncated in generated HTML
- **Member pages** (signup, signin, etc.) can be generated as static pages
- **Magic links** and authentication require server-side processing
- ⚠︎ **Consider** keeping auth pages dynamic even in static mode

Static + members is an advanced feature still in development.

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
2. Payment enabled as "support"
3. Customize upgrade page: "Buy me a coffee" style
4. Paid members get satisfaction of supporting

### Course or Ebook Access

1. Landing page is free (public)
2. Course content marked `audience: paid`
3. One-time payment unlocks all lessons
4. Lifetime access to materials

## Troubleshooting

**Payments not working?**

- Check Stripe keys are correct (test vs live mode)
- Verify webhook is set up and receiving events
- Check webhook signing secret matches

**Paywall not showing?**

- Confirm `audience: paid` is in frontmatter
- Check if you're logged in as a paid member (paywall hidden for you)
- Verify `show_paid_content: true` in members.yml

**Magic links not sending?**

- Check email configuration in your Rails app
- Verify ActionMailer is set up for production
- Check spam folder

**Upgrade button not appearing?**

- Confirm `payments.enabled: true` in members.yml
- Check if Stripe is connected
- Verify you have a price set

## Next Steps

1. **Customize your member pages** - Edit the copy in signup.md, upgrade.md, etc.
2. **Create your first paid post** - Add `audience: paid` and a paywall form
3. **Test the full flow** - Sign up, upgrade (using Stripe test mode), access content
4. **Set up webhooks** - Make sure payments automatically upgrade members
5. **Go live** - Switch to Stripe live keys when ready

The members system is designed to grow with you - start with free signups, add payments when you're ready, and customize everything to match your membership/publishing model.

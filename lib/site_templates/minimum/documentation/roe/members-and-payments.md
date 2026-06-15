---
roe_version: 0.0.26
title: "Features: Members"
status: published
---

# Members

Roe CMS includes a complete membership and payment system that allows you to:

- Build an email list with free member (and/or paid) signups
- Accept one-time payments for lifetime access to premium content
- Gate content behind a paywall with preview snippets
- Manage members and their access levels from the admin
- Accept donations from anyone visiting the site

The system is designed to be flexible: you can use it for free newsletters only, paid memberships only, or a combination of both. You can even use payments purely for donations/support without gating any content.

<mark>Note: Static-site generation does not support Members at this time. This is something we would love to add in the future but requires some work. For now, leave static-site-generation disabled if you want to have Members.</mark>

## Enabling the Members System

1. Go to <mark>Admin → Settings</mark>
2. Click **"Enable Members"**
3. Enable/disable Paid Memberships
  - Add your paid membership price
4. Enable/disable Newsletters
5. Choose if you would like to show free members/regular visitors paid content.
6. Click `ENABLE MEMBERS`

This creates:

- Your members configuration file
- Member [Pages](/admin/pages): signup, signin, upgrade, check-email, etc.

## Member Pages

When you enable members, Roe generates several pages that you can customize:

- `Sign up` | `signup.md` - Where people create free accounts
- `Sign in` | `signin.md` - Where members sign in with their email
- `Check your email` | `check-email.md` - Confirmation page after requesting a magic link
- `Upgrade` | `upgrade.md` - Where you pitch your paid membership
- `Donate` | `donate.md` - One-time support page (no account required)
- `Unsubscribe` | `unsubscribe.md` - Confirmation prompt before leaving the newsletter
- `Unsubscribed` | `unsubscribed.md` - Shown after a successful unsubscribe
- `Checkout success` | `checkout-success.md` - Stripe return URL after a successful paid-membership payment
- `Checkout cancel` | `checkout-cancel.md` - Stripe return URL when someone backs out of paid-membership checkout
- `Donation success` | `donation-success.md` - Stripe return URL after a successful donation
- `Donation cancel` | `donation-cancel.md` - Stripe return URL when someone backs out of a donation

These are regular markdown pages. You can edit the copy, add images, and customize them however you want.

## How Members Sign In (Magic Links)

Roe uses **passwordless authentication** for all members. When someone signs in:

1. They enter their email address
2. They receive an email with a "magic link"
3. They click the link and are automatically signed in
4. The link expires after 24 hours

Paid members can optionally use passwords (generated automatically after payment), but magic links still work for them too.

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

**How it works:**

- **Paid posts show** in collections (with paid-lock-icon if `show_paid_indicator: true`)
- **Clicking a paid post** will show a preview and paywall if you've added one to the post, otherwise, it redirects to the Upgrade page immediately.
- **Paid members** see all posts normally

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

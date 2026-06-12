---
roe_version: 0.0.9
title: Members
status: published
---

# Members

Roe CMS includes a complete membership system that allows you to:

- Build an email list with free member signups
- Manage members and their access levels from the admin

The system is designed to be flexible: you can use it for free newsletters only, paid memberships only, or a combination of both. Paid memberships and donations are handled separately — see [Payments](/documentation/payments).

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

## Configuration Options

Edit these in <mark>Admin → Settings → members.yml</mark>:

### Everyone Section

```yaml
everyone:
  show_paid_content: true
  show_paid_indicator: true
```

**`show_paid_content:`**

- If `true`, non-members can see paywalled posts (with truncation).
- If `false`, they won't see paid content on the site at all.

**`show_paid_indicator`** - Shows a small lock icon next to paid post titles/links.

For payment-related configuration (price, mode, donation amounts), see [Payments](/documentation/payments).

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

## Static Site Generation

If you're using static site generation, member features work differently:

- **Paywalled content** is properly truncated in generated HTML
- **Member pages** (signup, signin, etc.) can be generated as static pages
- **Magic links** and authentication require server-side processing
- ⚠︎ **Consider** keeping auth pages dynamic even in static mode

Static + members is an advanced feature still in development.

## Use Cases & Examples

### Free Newsletter Only

- Don't enable payments
- Use signups to build your email list
- All content is free
- Send newsletters to all members

For paid-membership and donation use cases, see [Payments](/documentation/payments).

## Troubleshooting

**Magic links not sending?**

- Check email configuration in your Rails app
- Verify ActionMailer is set up for production
- Check spam folder

For payment-related troubleshooting, see [Payments](/documentation/payments).

## Next Steps

1. **Customize your member pages** - Edit the copy in signup.md, upgrade.md, etc.
2. **Test the full flow** - Sign up, sign in via magic link
3. **Enable payments** - When you're ready to monetize, see [Payments](/documentation/payments)

The members system is designed to grow with you - start with free signups, add payments when you're ready, and customize everything to match your membership/publishing model.

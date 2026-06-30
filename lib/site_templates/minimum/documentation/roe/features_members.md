---
title: "Members"
status: published
url_name: members
tags: feature
related:
  - paid-content
  - stripe
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Members

Roe includes a complete membership system that allows you to:

- Build an email list with free member (and/or paid) signups
- Accept one-time payments for lifetime access to premium content
- Gate content behind a paywall with preview snippets
- Manage members and their access levels from the admin
- Accept donations from anyone visiting the site
- See [Payment Models](/documentation/payments#payment-models)

The system is designed to be flexible: you can use it for free newsletters only, paid memberships only, or a combination of both. You can even use payments purely for donations/support without gating any content.

<mark>Note:</mark> Static-site generation does not support Members at this time. This is something we would love to add in the future but requires some work. For now, leave static-site-generation disabled if you want to have Members.

## Enabling the Members System

1. Go to [Admin → Settings](/admin/configs)
2. Click `ENABLE MEBMBERS` (if you haven't already)
3. Enable/disable Paid Memberships
    - Add your paid membership price
3. Choose how you'd like paid content to be presented on the site
4. Finish setup with: `ENABLE MEMBERS`

This creates:

- Your members configuration (members.yml)
- [Member pages](/admin/pages): signup, signin, upgrade, check-email and more…

## Member Pages

When you enable members, Roe generates several pages that you can customize. These are regular Markdown pages — you can edit the copy, add images, and customize them however you want.

| Page | URL Name | Purpose |
|------|----------|---------|
| **Sign Up** | `sign-up` | Where people create free accounts |
| **Sign In** | `sign-in` | Where members sign in with their email |
| **Upgrade** | `upgrade` | Where you pitch your paid membership |
| **Check Your Email** | `check-email` | Confirmation page after requesting a magic link |
| **Support this site** | `donate` | Donation page for one-time contributions (no account required) |
| **Checkout - Success** | `checkout-success` | Shown after successful paid membership purchase |
| **Checkout - Cancel** | `checkout-cancel` | Shown if member cancels during checkout |
| **Donation - Success** | `donation-success` | Shown after successful one-time donation |
| **Donation - Cancel** | `donation-cancel` | Shown if donor cancels during donation |
| **Unsubscribe from Newsletter** | `unsubscribe` | Confirmation page before unsubscribing |
| **You've Been Unsubscribed** | `unsubscribed` | Confirmation page after successfully unsubscribing |

**Notes:**

- All pages use `audience: everyone` so they're accessible to visitors and members alike
- Pages contain special `form` [code blocks](https://www.markdownlang.com/basic/code.html#markdown-fenced-code-blocks) that Roe renders as working forms (signup, signin, checkout, etc.)
- The Account page (`/account`) is built into Roe and not customizable as a Markdown file but you can style it with CSS.
- Store checkout flows (`STORE` is enabled) have their own success/cancel pages separate from these

## How Members Sign In (Magic Links)

Roe uses *passwordless authentication* for members. When someone signs in:

1. They enter their email address
2. They receive an email with a "magic link"
3. They click the link and are automatically signed in
4. The link expires after 24 hours

*Paid members* can optionally use passwords (generated automatically after payment), but magic links still work for them too.

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

### Email Templates

Member emails are customizable Markdown files: [Admin → Emails](/admin/emails)

| Template | Purpose | Available Variables |
|----------|---------|---------------------|
| **magic_link** | Sent when someone requests to sign in | `@member_name`, `@member_email`, `@magic_link`, `@site_name` |
| **welcome** | Sent when someone creates a free account | `@member_name`, `@member_email`, `@site_name` |
| **upgrade_success** | Sent after successful paid membership purchase | `@member_name`, `@member_email`, `@password`, `@site_name`, `@account_url` |
| **email_changed** | Sent when a member changes their email address | `@member_name`, `@new_email`, `@old_email`, `@site_name` |
| **email_confirmation** | Sent to confirm a new email address (link must be clicked) | `@member_name`, `@confirmation_link`, `@site_name` |
| **payment_failed** | Sent when a recurring payment fails | `@member_name`, `@member_email`, `@update_payment_url`, `@site_name` |
| **membership_cancelled** | Sent when a member cancels their paid membership | `@member_name`, `@member_email`, `@site_name` |
| **account_deletion** | Sent when a member deletes their account | `@member_name`, `@member_email`, `@site_name` |

**Notes:**

- `Available Variables` are at the top of The Editor when editing email templates
- Variables use the `@variable_name` format in your templates
- All templates include `@member_name` and `@site_name` for personalization
- The `upgrade_success` email includes a generated `@password` — paid members need this password to sign in (free members use magic links only)
- `@magic_link` and `@confirmation_link` are full URLs that members click to complete actions
- Templates support full Markdown formatting including links, headings, and emphasis

## Static Site Generation

If you're using static site generation, `SSG` + `MEMBERS` is an advanced feature still in development.

## Next Steps

1. **Customize your member pages** - Edit the copy in signup.md, upgrade.md, etc.
2. **Enable newsletters** - To test emails ([Settings → Members](/admin/configs/members/edit))
3. **Enable payments** - When you're ready to monetize, see [Payments](/documentation/payments)

The members system is designed to grow with you - start with free signups, add payments when you're ready, and customize everything to match your membership/publishing model.

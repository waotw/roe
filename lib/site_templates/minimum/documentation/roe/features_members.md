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
- See [Payment Models](/documentation/roe/payments#payment-models)

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
| **Sign In** | `sign-in` | Where members sign in |
| **Upgrade** | `upgrade` | Where you pitch your paid membership |
| **Check Your Email** | `check-email` | Confirmation page after requesting a magic link (email sign-in only) |
| **Recover Account** | `recover-account` | Where a member resets a forgotten password with a recovery code (password sign-in only) |
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
- `check-email` and `recover-account` each only matter for one sign-in method — Roe shows whichever fits how your members sign in.

## How Members Sign In

Roe supports members **with or without email/Postmark**. You choose which when you set up Members, and you can switch later (see [Turning email off](#turning-email-off)). This setting only changes how members sign in; the rest of the Members features remain exactly the same.

### Email sign-in (magic links)

This is the default. When someone signs in:

1. They enter their email address
2. They receive an email with a "magic link"
3. They click the link and are automatically signed in
4. The link expires after 24 hours

There's no password to remember. Email sign-in needs a way to send mail — see [Email is optional](#email-is-optional) below.

### Password sign-in (no email)

If you'd rather not depend on email at all, turn email off and members sign in with an **email address and a password** instead. In this mode:

- New members **set a password when they sign up**.
- At signup they're shown a set of **recovery codes** — their way back in if they forget the password (there's no reset-by-email). More on these in [Recovery codes](#recovery-codes).
- There are no sign-in emails, confirmations, or newsletters, because Roe isn't sending email.

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

- **"Sign up free"** → Creates free account (sends a magic link, or asks for a password if email is off)
- **"Sign up and become a paid member"** → Creates account AND redirects to Stripe for payment

The upgrade button only appears if payments are enabled in your config.

**Just a link to sign-up?** For a call-to-action that sends readers to the sign-up page rather than embedding the form, use the Roe-anji [`subscribe` button](/documentation/roe/forms-and-buttons#subscribe-button) — a `button` block with `for: subscribe`.

### Email is optional

Email sign-in (magic links) needs a way to send email. If you're using it, set up [Postmark](/documentation/roe/postmark) — it appears in your settings as soon as Members is on.

If email isn't set up while email sign-in is on, Roe shows an orange dot beside your settings to remind you to set up email.

Newsletters are separate, and optional. Turn them on when you want to send posts to your free and paid members; leave them off and sign-in emails still work.

If you don't plan to send a newsletter, we recommend turning off email and members sign in with a password instead — see below.

### Turning email off

You can switch a site from email sign-in to password sign-in at any time: [Settings → Members](/admin/configs/members/edit).

A few things to know before you do:

- **Email turns off immediately.** Magic links stop working straight away.
- **New members** create a password when they sign up — nothing extra for you to do.
- **Existing members** need a password before they can get back in. While email is still on, **invite them from [Admin → Members](/admin/members)** — Roe sends each a temporary password to sign in with. Invite everyone you want to keep access *before* turning email off.

Roe walks you through this on the confirmation screen and links you to the Members page to send invites.

### Recovery codes

When a site uses password sign-in, each member gets a set of **8 recovery codes** the first time — shown **once**, at signup (or when you invite them). Each code resets the password one time. They're the only way back in if a member forgets their password, since there's no reset-by-email.

- A member can view status and generate a fresh set from their account page. Generating a new set replaces the old one — the previous codes stop working immediately.
- On the account page the codes are click-to-copy (one per line) so they're easy to save.
- A member resets a forgotten password on the **Recover Account** page by entering one of their codes; they're signed in automatically once it succeeds.

### Changing a password

A signed-in member can change their password from their account page (password sign-in sites). Roe asks for the current password first, then the new one twice. This is the routine change; recovery codes are only for when they're locked out.

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

- Member emails only send when email is on. With email off, Roe skips them — nothing is sent to an address that can't receive sign-in links anyway.
- `Available Variables` are at the top of The Editor when editing email templates
- Variables use the `@variable_name` format in your templates
- All templates include `@member_name` and `@site_name` for personalization
- The `upgrade_success` email includes a generated `@password` — paid members can use this password to sign in (free members on an email site use magic links only)
- `@magic_link` and `@confirmation_link` are full URLs that members click to complete actions
- Templates support full Markdown formatting including links, headings, and emphasis

## Member tokens

Each member has two tokens associtated with their membership.

| Token | What it does |
|-------|--------------|
| **Access token** | Signs them in. It's what a magic-link email carries — treat it like a password. |
| **Media token** | Gives them access to `paid` feeds, files and content. |

A site owner can see them for any member here: [Admin → Members](/admin/members).

A member's private feed addresses are listed on their account page: a paid feed from [feeds.yml](/documentation/roe/feeds-rss-atom), a podcast with paid episodes, or a music release with paid tracks. Each has a Copy button, and **Refresh your private links** issues a fresh set if one gets shared — the old links stop working straight away. The benefit of a media token is that they don't have to sign in to their account to access files. This is what allows them to subsribe in a podcast or RSS reader without being signed in.

Cancelling an account will invalidate both tokens. A cancelled or downgraded member's media token stops opening files immediately.

## The Account Page

Every member manages their own account at `/account`. What shows there depends on the member and how your site is set up:

- **Name and email** — editable by the member. On an email site, changing the email sends a confirmation link to the new address; with email off the change is immediate.
- **Receipt** — paid members see a link to their Stripe receipt (or a note that Stripe emailed it). See [Admin → Members](/documentation/roe/admin_members) for the owner-side view.
- **Change password** and **recovery codes** — only on password sign-in sites (see above).
- **Newsletter** — subscribe/unsubscribe, shown only when newsletters are turned on and configured.
- **Private feed links** and **Refresh your private links** — see [Member tokens](#member-tokens).
- **Delete account** — removes identifiable information; asks the member to type a confirmation word first.

## Static Site Generation

Currently, the members system is not supported for SSG. You can only have public files in your static site but you can use the Store feature to sell tracks and other digital files: [Feature → Store](/documentation/roe/store)

## Next Steps

1. **Customize your member pages** - Edit the copy in signup.md, upgrade.md, etc.
2. **Enable newsletters** - To test emails ([Settings → Members](/admin/configs/members/edit))
3. **Enable payments** - When you're ready to monetize, see [Payments](/documentation/roe/payments)

The members system is designed to grow with you - start with free signups, add payments when you're ready, and customize everything to match your membership/publishing model.

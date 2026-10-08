---
title: Admin → Members
status: published
url_name: admin_members
tags:
- admin
related:
- members
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Manage your Members

Members are able to edit their accounts by signing in and going to `/account`. Users can:

- edit their name and email
- upgrade
- cancel their membership
- see a receipt link for their payment
- delete their accounts (this cannot be undone and requires confirmation)
- unsubscribe or resubscribe to the newsletter (if enabled)
- change their password and view/regenerate recovery codes (if email is disabled)

## [Admin → Members](/admin/members)

This is the section that allows you to see all members, edit their tier, cancel their membership, delete their account, edit their name/email.

You can click on any email address or `View/Edit` to see the full details of each account.

### Inviting members (password sign-in)

Roe supports email through Postmark and if you have email enabled and configured, Roe will send sign-in links to your members so they can sign in. Roe also supports password sign-in if email is disabled.

When your site uses password sign-in (email off), existing members need a password before they can get back in. From the Members page you can **invite** a member — Roe sends them a temporary password to sign in with. You compose the email before it's sent. <mark>Note:</mark> Email must be on and configured to send invites.

This matters most right before you turn email off: invite everyone that needs to sign-in before you turn off email. New members who sign up after email is off create their own password, no invite needed.

### Deleting members

What happens when an account is deleted (by the site owner or by the member themselves) depends on the state of the account:

- If the account has no payment, delivery or order history, it is completely removed from the database.
- If an account has payment, delivery or order history, the email and name of the member is deleted but the history is kept for your records.

Either option removes all user identifiable information from the account.

### Permanently delete accounts

If you don't need the payment, delivery or order history for an account, you can delete it permanently. On your [Members](/admin/members) page:

1. Open the account status filter and choose `Deleted`.
2. Select a deleted member by clicking the checkbox on the left of the account
    - This will bring up the bulk action menu. You can choose to `SELECT ALL VISIBLE` here.
3. Click `DELETE PERMANENTLY` and confirm.

These accounts and any information in them are gone.

### Filters

- Use the tabs: `ALL`, `FREE`, `PAID` to see those members only.
- You can filter by `status`, `newsletter status` and then `sort` or search.

### Payment History (memberships and donations)

Click on a member's email to reveal their page. This page lists their payments — memberships and donations alike. Each payment links straight to that payment in Stripe (**Receipt & Refund**), where you can:

- view the receipt,
- issue a refund.

Refunds and receipts are handled in Stripe, not inside Roe — the link just takes you to the right place. The link lands in the matching Stripe environment (test or live). The payment's reference stays on the record even if the account is later deleted, so a payment can still be matched in Stripe.

### Payments

For payment-related configuration (price, mode, donation amounts), see: [Settings → Members](/documentation/roe/settings-members).

---
title: "Members"
status: published
url_name: admin_members
tags: admin
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

Members are able to edit their accounts by signing in and going to `/account`. Users can upgrade, cancel their membership and delete their accounts.

## [Admin → Members](/admin/members)

This is the section that allows you to see all members, edit their tier, cancel their membership, delete their account, edit their name/email.

### Deleting members

What happens when an account is deleted (by the site owner or by the member themselves) depends on the state of the account:

- If the account has no payment or delivery history, it is completely removed from the database.
- If an account has payment or delivery history, the email and name of the member is deleted but the history is kept.

Either option removes all user identifiable information from the account.

### Filters

- Use the tabs: `ALL`, `FREE`, `PAID` to see those members only.
- You can filter by `status`, `newsletter status` and then `sort` or search.

### Payments

For payment-related configuration (price, mode, donation amounts), see: [Settings → Members](/documentation/roe/settings-members).

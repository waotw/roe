---
title: "Settings → Members"
status: published
url_name: settings-members
tags: settings
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

# Members, Newsletter & Paid Content Settings

## Display

`Always show member icon`

- When `checked` the member/account icon is visible at all times
  - if signed-out it links to the `/sign-in` page.
  - if signed-in it links to their account page.
- When `unchecked`, the member icon will only show up for signed-in members. 

## Sign-in method (email on/off)

| Setting | Description |
|---------|-------------|
| `Member email: Email enabled` | `checked` (default): members sign in with an emailed magic link. <br>`unchecked`: members sign in with an email address and a password instead, and Roe sends no member email. |

**Notes:**

- With email **on**, members sign in with a magic link and you'll need [Postmark](/documentation/roe/postmark) set up so the link can be sent.
- With email **off**, members set a password at signup and get recovery codes; there are no sign-in emails, confirmations, or newsletters. See [Members → How Members Sign In](/documentation/roe/members#how-members-sign-in).

## Payments

| Setting | Type | Description |
|---------|------|-------------|
| `enabled` | Boolean | Enable paid memberships and/or donations |
| `mode` | String | `memberships` (default), `donations`, or `both` |
| `price` | String | Membership price (e.g., `"29.00"`) |
| `donation_amounts` | Array | Preset amounts for donation buttons: `[5, 10, 20, 50]` |

**Mode options:**

- `memberships` — One-time payment for lifetime access
- `donations` — One-time contributions, no account required  
- `both` — Enable both memberships and donations

## Newsletter

| Setting | Type | Description |
|---------|------|-------------|
| `enabled` | Boolean | Enable newsletter broadcasts via Postmark |

**Note:** Newsletters need email. They're unavailable when member email is turned off.

## Paid Content

| Setting | Type | Description |
|---------|------|-------------|
| `everyone.show_paid_content` | Boolean | `true` shows paid posts to everyone with a lock icon; `false` hides them from non-paid members |

**Notes:**

- All settings live in `site/system/features/members.yml`
- Payments require Stripe integration configured in [Admin → Settings Integrations](/admin/configs/payments/edit)
- Newsletters and emails require Postmark integration configured in [Admin → Settings Integrations](/admin/configs/newsletters/edit)
- The `price` is synced to Stripe as a product/price when you save the members config
- `donation_amounts` only appears when mode is `donations` or `both`

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

`Always show member icon` - Check this box to keep the account icon visible at all times. When `uchecked`, the member icon will only show up for signed-in members. 

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

## Paid Content

| Setting | Type | Description |
|---------|------|-------------|
| `everyone.show_paid_content` | Boolean | `true` shows paid posts to everyone with a lock icon; `false` hides them from non-paid members |

**Notes:**

- All settings live in `site/system/features/members.yml`
- Payments require Stripe integration configured in [Admin → Settings Integrations](/admin/configs/payments/edit)
- Newsletters require Postmark integration configured in [Admin → Settings Integrations](/admin/configs/newsletters/edit)
- The `price` is synced to Stripe as a product/price when you save the members config
- `donation_amounts` only appears when mode is `donations` or `both`

---
title: "Paid Content"
status: published
url_name: paid-content
tags: content
---

##### Related documentation

```collection
source: documentation
related: true
limit: all
template: links
```

# Paid Content

In order to add Paid Content, you'll need to enable `MEMBERS` and turn on `Payments` in the Members settings. You can enable here: [Admin → Settings](/admin/configs), click `ENABLE MEMBERS`, then enable `Payments` for `Members`.

You can also choose whether or not to show paid content to everyone or just paid members. 

## Creating Paid Content

Once you enable `Payments`, an `ADD PAYWALL` button shows up in [The Editor](/documentation/the-editor). This allows you to easily add your paywall.

To make a post or page premium/paid-only:

### 1. Set the Audience

Add this to your post/page frontmatter:

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

- **Paid members** see the entire post (paywall form is hidden)
- **Free members & guests** see everything up to the form, then they see the paywall
- **The form** shows an upgrade button linking to the [Members page](/admin/pages): `/upgrade`

**In the editor:** When editing a post with `audience: paid`, you'll see a green `ADD PAYWALL` button in the toolbar. Click it to insert the paywall form block instantly.

### 3. Without a Paywall Form

If you mark a post as `audience: paid` but don't add a paywall form, visitors who try to access it will be redirected to your `/upgrade` page.

## Smart Upgrade Buttons

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | Must be `checkout` |
| `member-button-text` | No | For logged-in members |
| `non-member-button-text` | No | For non-members (shows sign-up link) |

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

This creates a better experience - everyone sees the right call-to-action for their situation.

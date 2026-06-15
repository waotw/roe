---
roe_version: 0.0.26
title: "Content: Paid/premium"
status: published
---

# Paid Content

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

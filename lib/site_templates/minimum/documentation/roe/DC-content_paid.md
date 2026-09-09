---
title: "Paid Content"
status: published
url_name: paid-content
tags: content
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Paid Content

In order to add Paid Content, you'll need to enable `MEMBERS` and turn on `Payments` in the Members settings. You can enable here: [Admin → Settings](/admin/configs), click `ENABLE MEMBERS`, then enable `Payments` for `Members`.

You can also choose whether or not to show paid content to everyone or just paid members. Public visitors and free members will see previews of the paid content.

## Creating Paid Content

Once you enable `Payments`, a **Paywall** option appears in the `ACTION ▼` menu of [The Editor](/documentation/roe/the-editor) — a quick way to drop in a paywall form.

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

You can control where the paywall appears in your content using a `paid_content` form block. The editor helps you write these with the `ACTION ▼` → `P [The Editor](/documentation/roe/the-editor) — a quick way to drop in a paywall form.

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

**In the editor:** When payments are enabled, the `ACTION ▼` menu includes a **Paywall** option. It opens the form builder already set to the paid-content block — keep the default message and button text or edit them, then insert.

### 3. Without a Paywall Form

If you mark a post as `audience: paid` but don't add a paywall, visitors who try to access it will be redirected to your `/upgrade` page.

## Media files and paid content

Adding `audience: paid` to a post or page's metadata will protect any media files in the content of that post or page. Direct links to those files are blocked as well.

#### There are a few exceptions:

- Roe allows you to give previews of paid content. Any media files in the content above the paywall will be public.
- Posts and pages can have an `image` in their metadata. These images will always remain public.
- <mark>A media file that is referenced in both paid and free content stays public.</mark>

#### How to know if media is public or protected

 The [Media browser](/documentation/roe/media#audiences) allows you to filter by `paid` and `free` media so you can verify if something is protected. Check both `paid` and `free` to find files that are in `paid` posts but are still public.

![Roe - Media Browser with Paid and Free filters checked](/media/images/media_paid_free.png)

### Podcasts and music

Paid members are given private feeds for podcasts and music. If a user cancels their account, thier private links will no longer work. See [Podcast feeds](/documentation/roe/podcast-feed-tags#feed-urls).

## Paid podcasts and releases

In Roe, you can add `audience: paid` to the podcast or music release globally. This will set all episodes or tracks as paid. However, you can override this for individual episodes or tracks.

An episode that sets `audience: everyone` overrides the global setting for that episode:

```yaml
---
title: Episode 1 — Come In
podcast: my-show
audience: everyone
---
```

### How people subscribe

If a podcast contains at least one free episode, there will be a public feed which contains the free episodes and previews of the paid episodes. Previews appear in the public feed with their title and description but no audio file.

Music releases work the same way — see [Settings → Music](/documentation/roe/settings-music#paid-music).

## Upgrade Buttons

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `checkout` |
| `member-button-text` | No | For logged-in members |
| `non-member-button-text` | No | For non-members (shows sign-up link) |

The upgrade form shows different buttons depending on who's viewing it:

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

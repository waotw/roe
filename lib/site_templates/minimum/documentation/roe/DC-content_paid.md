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

If you mark a post as `audience: paid` but don't add a paywall form, visitors who try to access it will be redirected to your `/upgrade` page.

## Files behind paid content

Marking a post paid also protects the files it uses. An audio file, image or video that only paid content points at is served to paid members, admins, and nobody else — anyone else gets a 403, even with the exact URL.

This is worth knowing because it wasn't always true. A gated page hides its own links, but the file underneath sat at a guessable address; anyone who had the URL kept it, including someone who had since cancelled.

Roe works out which files to protect from what references them. A file is protected when **every** post or page using it is paid.

<mark>A file used by both paid and free content stays public.</mark> That's deliberate: the alternative is that editing an unrelated paid post silently breaks an image on a page anyone can read. If something you meant to protect is readable, this is usually why — find it with the `Paid` and `Free` toggles together in the [Media browser](/documentation/roe/media#audiences).

Resized copies of an image are protected with their original, so a paid photo can't be read at 800px instead.

### Paid members reading on your site

Nothing to do. A signed-in paid member's session carries them, so images and audio load as they'd expect.

### Podcast and music apps

An app fetching an episode has no session, so private feeds put a token in each file's URL. That token is unique to the member, grants reading files and nothing else, and stops working the moment they cancel or downgrade. See [Podcast feeds](/documentation/roe/podcast-feed-tags#feed-urls).

## Paid podcasts and releases

A podcast or a music release carries an audience of its own, and its episodes or tracks inherit it. Set the show to `paid` and everything in it is paid, without editing each episode.

An episode that sets its own audience overrides the show. That's what lets you sell a paid podcast with free openers:

```yaml
---
title: Episode 1 — Come In
podcast: my-show
audience: everyone
---
```

Leave `audience` off an episode and it follows the show. Set it, and it doesn't.

Resolution is the same everywhere in Roe: **the episode, then its show, then everyone.**

### What people can subscribe to

A public feed exists whenever the show has something public in it — not simply when the show isn't paid.

| Show | Episodes | Public feed |
|------|----------|-------------|
| free | some paid | the free ones, with paid as previews |
| paid | some free | the free ones |
| paid | none free | none at all |

So a paid podcast with three free openers has a feed people can subscribe to, hear the openers, and upgrade from. A paid podcast with nothing free has no public feed, and the only way in is the private one.

Previews count as public: with **Show paid content** on, paid episodes appear in the public feed with their title and description but no audio.

Music releases work the same way — see [Settings → Music](/documentation/roe/settings-music#paid-music).

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

---
title: Roe-anji → Forms & Buttons
status: published
url_name: forms-and-buttons
tags: roe-anji
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Forms & Buttons

Two Roe-anji blocks add interactive elements to your content: `form` (membership, payment, and newsletter flows) and `button` (store "add-to-cart" buttons, plus share and subscribe actions).

## The `for:` selector

This determines what the `form` or `button` is for…

| `for:` value | What it renders |
|---|---|
| *(omitted)* / `product` | Store purchase button (the default) |
| `share` | Share button (native share sheet / copy + email menu) |
| `subscribe` | "Subscribe" button linking to the member sign-up page |

---

# Buttons

## Product buttons (default)

Add a product purchase button. On a product page the SKU is auto-detected; elsewhere, name it.

````markdown
```button
sku: PRODUCT-SKU-GOES-HERE
text: Add to Cart
style: primary
quantity: 1
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `sku` | No | Product SKU — auto-detects on product pages if omitted |
| `text` | No | Button text — default "Add to Cart" |
| `style` | No | `primary` (default), `secondary`, or `outline` |
| `quantity` | No | Default quantity — default 1 |

For more information about product buttons and how they work, see [Store](/documentation/roe/store) for the full picture.

## Share button

A share button for the current page. On touch devices it opens the native OS share sheet; on desktop it reveals a small **Copy link** + **Email** menu.

````markdown
```button
for: share
```
````

By default it shares the page's canonical URL and its [og:title](/documentation/roe/glossary#open-graph-og), so links shared on social media have the right link/title. Override any of that:

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `share` |
| `label` | No | Button text — default "Share" |
| `url` | No | URL to share — default: the page's full URL |
| `title` | No | Title to share — default: the page's `og:title` |
| `text` | No | Extra text passed to the native share sheet |
| `style` | No | Descriptive word/s that add CSS classes to button (e.g. `style: small-center` → `share-small-center`) |

**Styling:** the wrapper always carries a stable `.share` class (plus a `share-<token>` for each `style:` word), so a theme can align or restyle every share button at once. It's `inline-flex` by default, so to center them all: `.share { display: flex; justify-content: center }`.

## Subscribe button

A "Subscribe" button that links to the member **sign-up** page. On a Roe site, subscribing means becoming a member (this includes newsletters). This button links to your [member sign-up](/documentation/roe/members#member-pages) page.

````markdown
```button
for: subscribe
```
````

The subscribe button only works if Members is enabled for your site. With members turned off there's no sign-up page to link to, so nothing renders (you'll see a local-only warning).

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `subscribe` |
| `label` | No | Button text — default "Subscribe" |
| `url` | No | Link target — default `/sign-up` |
| `style` | No | Descriptive word/s that add CSS classes to button (e.g. `style: large-subscribe` → `members-large-subscribe`) |

---

# Forms

Forms provide interactive elements for [memberships](/documentation/roe/members), [payments](/documentation/roe/payments), and the [newsletter](/documentation/roe/newsletters). Each is selected with `for:`.

## Signup

````markdown
```form
for: signup
button-text: Sign Up
upgrade-button-text: Upgrade now
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `signup` |
| `button-text` | No | default "Sign Up" |
| `upgrade-button-text` | No | Optional second button for immediate upgrade |

## Signin

````markdown
```form
for: signin
button-text: Send Magic Link
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `signin` |
| `button-text` | No | Button text — default "Send Magic Link" |

## Checkout

````markdown
```form
for: checkout
member-button-text: Upgrade
non-member-button-text: Sign up to upgrade
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `checkout` |
| `member-button-text` | No | For logged-in members |
| `non-member-button-text` | No | For non-members (shows sign-up link) |

## Donate

````markdown
```form
for: donate
button-text: Donate
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `donate` |
| `button-text` | No | Button text — default "Donate" |

Uses the donation amounts from your `members.yml` config.

## Unsubscribe

````markdown
```form
for: unsubscribe
button-text: Unsubscribe
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `unsubscribe` |
| `button-text` | No | Button text — default "Unsubscribe" |

## Paid Content (paywall)

````markdown
```form
for: paid_content
text: This is premium content. Upgrade to continue reading.
button-text: Become a paid member
```
````

| Option | Required | Description |
|--------|----------|-------------|
| `for` | Yes | `paid_content` |
| `text` | No | Message shown above the upgrade button |
| `button-text` | No | CTA text — default "Become a paid member" |

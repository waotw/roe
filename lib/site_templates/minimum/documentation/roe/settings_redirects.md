---
title: "Settings → Redirects"
url_name: redirects
status: published
tags: settings
related:
  - guide-publish
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Edit your Redirects

A redirect sends visitors from one URL to another, so a link that used to work keeps working. Edit them in the Admin at [Settings → Redirects](/admin/configs/redirects/edit). Click `SAVE` when you're done.

Two examples of why this is useful:

- **You moved to Roe from somewhere else on the same domain.** For example, Substack publishes posts with this pattern `/p/my-post` and Roe publishes them like this `/posts/my-post`. Importing rewrites the links inside your content, but it can't reach the links pointing to your site from outside — search results, other people's sites, newsletters you've already sent.
- **You renamed something.** Changing a post's `url_name` is routine in Roe, and it quietly breaks every existing link to that page.

The Redirects page shows your current redirects in a table, with the file itself below it for editing. Roe reads them from one file, `site/system/global/redirects.yml`, which syncs between your local and live sites like the rest of your content.

## Roe can add them for you

When you rename something that's already published — change its `url_name`, or its title — the old address stops working. So when you save that change, Roe offers to create the redirect for you, from the old URL to the new one. Accept it and the redirect is written to `redirects.yml` automatically.

If you later change the address again, Roe keeps the chain tidy: every old URL points straight at the current one, in a single hop. And if you change it back to what it was, Roe clears the redirect it no longer needs.

## Creating one by hand

You can also add, change, or remove redirects yourself on this page. The previous path goes on the left (before the `:`) and the destination path goes on the right.

```yaml
redirects:
  /old-about: /about
```

If someone visits your site and goes to `/old-about`, Roe will give them `/about`. You can also send them to a different URL entirely: `/old-about: https://my-new-about-page-website.com`

If two rules match a previous path, the first match in the file will be used. Best practice is to put specific rules above wildcard rules. For example:

```yaml
redirects:
  /p/welcome: /hello
  /p/*: /posts
```

In this case, `/p/welcome` will be sent to `/hello` and not to `/posts/welcome`.

## Using a wildcard to match many paths

You may want to redirect a bunch of paths at once. You can use `/*` as a wildcard at the end of a rule.

```yaml
redirects:
  /p/*: /posts
```

In the above example `/p/welcome` goes to `/posts/welcome`, `/p/2024/summer` goes to `/posts/2024/summer`, and `/p` on its own goes to `/posts`. Write the destination without a trailing `/` as above.

## Choosing the response

By default, Roe uses a **301** status, which means a permanent redirect. This tells search engines that this new page is a permanent replacement of the previous one; the new URL gets indexed and inherits the old page's ranking.

When you want something else, give the rule a `to` and a `status`:

```yaml
redirects:
  /shop: /store
  /sale:
    to: /store/summer-sale
    status: 302
```

| Status | Meaning | Use it when |
|--------|---------|-------------|
| `301` | Moved permanently | The page has moved for good. The default. |
| `302` | Found, temporarily elsewhere | A seasonal or short-lived detour. |

## Roe won't redirect everything

Roe's own addresses are off limits: `/admin`, `/system`, `/rails`, `/webhooks` and `/api`.

Roe will ignore **a rule that points at itself**, such as `/blog/*` sending everything to `/blog`.

## If the file won't save

Roe checks the file is valid before saving. If there's a typo in the YAML, it keeps your existing redirects in place and shows you the error, rather than saving a broken file that would drop every redirect at once.

## A full example

```yaml
redirects:
  /old-about: /about
  /shop: /store
  /p/*: /posts
  /newsletter/*: /posts
  /sale:
    to: /store/summer-sale
    status: 302
```

Query strings are carried across, so `/p/welcome?ref=twitter` arrives at `/posts/welcome?ref=twitter` with the tracking intact.

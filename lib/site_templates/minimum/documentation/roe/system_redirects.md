---
title: Redirects
status: published
tags: system
related:
---

# Redirects

A redirect sends visitors from one URL to another. Here are two examples of how this is useful:

- **You moved to Roe from somewhere else on the same domain.** Substack publishes posts with this pattern `/p/my-post` and Roe publishes them like this `/posts/my-post`. Importing rewrites those links inside your own content, but it can't reach the links pointing to your site from outside — search results, other people's sites, newsletters you've already sent.
- **You renamed a page.** Changing a page's `url_name` is routine in Roe, and it quietly breaks every existing link to that page.

Roe reads its redirects from one file: `site/system/global/redirects.yml`.

## Creating a redirect

The previous path goes on the left (before the `:`) and the destination path goes on the right.

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

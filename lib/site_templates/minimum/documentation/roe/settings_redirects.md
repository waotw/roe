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
- **You renamed something.** Changing a `url_name` is easy in Roe, and it quietly breaks every existing link to that post, page or product.

The Redirects page shows your current redirects in a table, with the file itself below it for editing. Roe reads them from one file, `site/system/global/redirects.yml`, which syncs between your local and live sites like the rest of your content.

## Roe can add them for you

The `url_name` for a post, page or product is set by:

- the `title`. Roe creates the `url_name` from the `title` automatically.
- the `url_name` in the metadata (this always wins)

When the `url_name` is changed for any `published` post, page or product, Roe will give you these options:

- `SAVE NEW URL & REDIRECT` — use the new address and forward the old one so existing links keep working.
- `SAVE WITH OLD URL` — keep the previously saved address (undo just the rename) and save your other edits.
- `CANCEL` — don't save anything; go back to the editor.

If you later change the address again, Roe keeps the redirects tidy: every old URL points straight at the current one, in a single hop. And if you change it back to the original `url_name`, Roe clears the redirect as it's no longer needed.

## Creating one by hand

You can also add, change, or remove redirects yourself on this page: [Settings → Redirects](/admin/configs/redirects/edit). The previous path goes on the left (before the `:`) and the destination path goes on the right.

```yaml
redirects:
  /old-about: /new-about
```

If someone visits your site and goes to `/old-about`, Roe will give them `/new-about`. You can also send them to a different URL entirely: `/old-about: https://my-new-about-page-website.com`

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

In the above example `/p/welcome` goes to `/posts/welcome`, `/p/2024/summer` goes to `/posts/2024/summer`, and `/p` on its own goes to `/posts`. ==Note:== Write the destination without a trailing `/` as above.

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

Roe checks the file is valid before saving. If there's a typo in the YAML, it keeps your existing redirects in place and shows you the error to avoid saving a broken file and breaking the other redirects.

## A full example

```yaml
redirects:
  /old-about: /new-about
  /shop: /store
  /p/*: /posts
  /newsletter/*: /posts
  /sale:
    to: /store/summer-sale
    status: 302
```

Query strings are carried across, so `/p/welcome?ref=twitter` arrives at `/posts/welcome?ref=twitter` with the tracking intact.

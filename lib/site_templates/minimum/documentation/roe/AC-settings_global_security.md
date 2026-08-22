---
title: "Settings → Security"
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

# Edit your Security Settings

Your Security Settings cover two things: which AI crawlers may read your site, and how often anyone can use the parts of it that send email or create accounts. Edit them in the Admin at [Settings → Security](/admin/configs/security/edit). Click `SAVE` when you're done.

Note that publicly available web pages can be scraped if someone (or a company) is intent on doing so. Roe's best defense against this is it's Members system which keeps `paid` posts and pages private unless someone actually has a paid account.

## AI Crawlers

Roe writes a `robots.txt` for your site describing which crawlers you'd rather stay away. You can see yours at `/robots.txt`.

Three choices:

- `Block training and AI answers` — the default. Keeps your writing out of the collections used to train AI models, and out of AI search results.
- `Block training only` — keeps your writing out of training sets, but lets tools like ChatGPT and Perplexity read a page to answer someone's question, usually with a link back to you.
- `Allow everything` — no AI-specific rules.

Ordinary search engines are never blocked, whichever you choose. Google, Bing and Apple each publish a separate name for their AI training crawler, and those are the ones Roe blocks — so your site carries on appearing in search results as normal.

### What this can and can't do

`robots.txt` is a request, not a lock. The large, well-known crawlers should honor it — being caught ignoring a published request can be a bigger problem for them than the data they can gather. However, that only matters if companies are held accountable for scraping copy written material without permission and currently, that isn't happening.

Anything that genuinely must not be read by a machine belongs behind a [paid audience setting](/documentation/roe/paid-content) instead, which Roe enforces on the server.

### The cost of blocking AI answers

The default blocks both. That keeps your work out of training sets, and it also takes your site out of AI answers — the results where a tool quotes you and links back. Some writers want exactly that; others find it a useful way for readers to find you.

If you'd like to be cited, choose `Block training only`.

## Rate Limiting

The rest of this page limits how often the same person can do something expensive: request a sign-in email, create an account, or try a link with a token in it. It slows down abuse of those pages.

It is not protection against a denial-of-service attack. A flood of traffic is stopped by your host or a service like Cloudflare, before it ever reaches Roe.

Turn it off by unchecking `Limit repeated requests` if you'd rather have none of it.

### The limits

Each has two numbers: how many attempts are allowed, and how many minutes those are counted over.

- `Sign-in emails` — how many sign-in links one email address can be sent. Counted per address, so that one person asking repeatedly can't use up anyone else's.
- `Sign-ups` — how many accounts can be created from one connection.
- `Sign-up with checkout` — the same, for sign-ups that go straight to payment.
- `Link and token attempts` — how often sign-in links and unsubscribe links can be tried from one connection.

The defaults are deliberately loose. You shouldn't be able to reach them by using your own site normally, and neither should your readers.

### What happens at the limit

Reaching the sign-in limit doesn't lock anyone out. Roe stops sending another email and says one is already on its way — which is true, and usually what someone clicking twice needed to hear.

Two decisions behind that are worth knowing, because they're the reason this shouldn't ever leave a real visitor stranded:

Sign-in emails are counted **per email address, not per connection**. Whole offices, universities and mobile networks share a single connection between thousands of people. Counting sign-ins that way is how someone ends up unable to reach their own account because of a stranger on the same network.

### If you set something too low

A value that would refuse everyone — zero, or blank — is read as "not set" and the default is used instead. A typo here shouldn't be able to lock your readers out of your site.

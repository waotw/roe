---
roe_version: 0.0.19
title: Feeds (RSS & Atom)
status: published
---

# Feeds

The system will automatically generate an RSS and Atom feed at these urls:
- RSS: `/feed.xml`
- Atom: `/feed.atom`

The system will give generate a description for each post:
- if the post has an `excerpt`, the excerpt will be used.
- if the post has a `subtitle`, but not `excerpt`, the subtitle will be used. 
- if a post has neither `subtitle/excerpt`, the first paragraph of the post will be used and truncated as needed.

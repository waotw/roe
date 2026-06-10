---
title: Podcasts
status: published
---

# Podcasts

## Global Settings

To create a podcast, go to the Settings page and click the `ADD PODCAST` button. This will generate the settings file (`podcast.yml`) and edit it.

These are the global settings for your podcast and all should be filled in. A breakdown of these settings and what they represent can be found here: [Podcast Feed & Tags](/documentation/podcast-feed-tags).

## Episode

To create a podcast episode:

1. create a new post
2. change the `post_type` to `podcast`
3. fill in all the required fields.

<mark>Note: Podcasts must have a:</mark> `GUID`. This is a global unique identifier for each episode. This is what allows you to change info about an episode after it's been published and not cause mayhem. All the podcast diretories and apps look for this `GUID` to identify the episode. Roe will do it's very best to not allow you to delete or change the `GUID`. It is added to the post metadata automatically when you publish an episode and will be re-added if it is ever deleted or changed.

## Podcast Settings Breakdown

```bash
┌─────────────────────────────────┐
│  Podcast Settings               │
│  (podcast.yml)                  │
└────────────┬────────────────────┘
             │
             │ defaults flow down
             ↓
┌─────────────────────────────────┐
│  Episode Post                   │
│  (Post metadata)                │
│                                 │
│  • Can override defaults        │
└────────────┬────────────────────┘
             │
             │ combined data
             ↓
┌─────────────────────────────────┐
│  Podcast Feed                   │
│  (Generated RSS/XML)            │
│                                 │
│  Final feed with all tags       │
│  Ready for Apple/Spotify        │
└─────────────────────────────────┘
```
curl -L -o test.mp3 -A "Mozilla/5.0" "https://api.substack.com/feed/podcast/<the_failing_episode_url_with_token>"

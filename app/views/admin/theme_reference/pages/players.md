The player card for audio and video, and a player with its playlist. Every track is the same short sample clip.

## Audio player card

```card
type: player
audio: /admin/themes/reference/media/sample-audio.mp3
title: Field Notes 1 - Starting Out
image: /admin/themes/reference/media/sample-5.jpg
```

## Audio player card without artwork

```card
type: player
audio: /admin/themes/reference/media/sample-audio.mp3
title: Morning Song
show_artwork: false
```

## Video player card

```card
type: player
video: /admin/themes/reference/media/sample-video.mp4
title: A Short Film
```

## Player and podcast playlist

```card
type: player
```

```collection
template: playlist
source: posts
post_type: podcast
tags: theme-reference-podcast
order: episode_number
```

If a player doesn't have a collection or playlist, it will play the first playlist after it in the markdown file. If there isn't one, it will play the first playlist on the page.

```card
type: player
```

This is no playlist directly below the above player but it will load this one:

```collection
template: playlist
source: posts
post_type: podcast
tags: theme-reference-podcast
order: episode_number
```

## Player and music playlist, folded

```card
type: player
```

```collection
template: playlist
source: posts
post_type: music
tags: theme-reference-music
order: track_number
heading: Sample Album
fold: true
```

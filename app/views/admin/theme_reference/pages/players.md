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

A player with nothing of its own to play takes the first track of the playlist under it.

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

## Music playlist, folded

```collection
template: playlist
source: posts
post_type: music
tags: theme-reference-music
order: track_number
heading: Sample Album
fold: true
```

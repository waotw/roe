---
title: Cards
status: published
url_name: cards
tags: roe-anji
---

##### Related documentation

```collection
source: documentation/roe
related: true
template: links
```

# Cards

```card
type: aside
text: This is an aside which is adding some helpful info about this paragraph.
``` 

Cards use a similar syntax to [Collections](/documentation/roe/collections) and allow you to embed styled elements directly in a Markdown file: [pullquote ↓](#pull-quote), [post link ↓](#post-link), [aside ↓](#aside), [product link ↓](#product-link), [player ↓](#player).

To make things a bit easier, each card `type` has it's own defaults. The card defaults can be edited in [Admin/Settings](/admin/configs/cards/edit).

Use the `CARD ▼` button in The Editor to add a card without writing the block by hand. Choose a card type and its fields appear — fill in the ones you want (blanks are left out) and it drops the finished `card` block at your cursor. It won't insert until the required fields are filled, helps avoid broken cards. For `post-link` and `product-link` cards, the `post`/`product` field is a search box: start typing, pick the item, and the card pulls in its title, image, and other details automatically; shown as the placeholders which can be overwritten.

## Pull quote

Markdown supports block quotes but not pull quotes. The Pullquote Card allows you to add them easily.

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `pullquote` |
| `text` | Yes | The quote content |
| `attribution` | No | Who said it — displays with em-dash |
| `position` | No | `center` (default), `left`, or `right` - you can set the default in Settings → Defaults → cards.yml|

To connect a pullquote to a particular paragraph, put it directly above that paragraph with no line between them.

### Examples

````markdown 
```card
type: pullquote
text: There's only one way to find out…
```
````

↑ This code will look like this ↓ :

```card
type: pullquote
text: There's only one way to find out…
```

You can also add `attribution` if this quote is from someone specific:

````markdown 
```card
type: pullquote
text: There's only one way to find out…
attribution: great philosopher
```
````
↑ Above looks like this ↓ :

```card
type: pullquote
text: There's only one way to find out…
attribution: great philosopher
```

### position
(default: `center`)

You can also use `position` parameter: `left`, `right`. This allows the pullquote to be amoung the text and have the text flow around it. Like this: (try resizing the window to see how it flows.)

---

```card
type: pullquote
text: Your not gonna be picking a fight, Dad, dad dad daddy-o.
position: right
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

↑ To achieve that, you just have to give the Pullquote a `position` of `right` and put the Pullquote directly above the paragraph you want the Pullquote to interact with, like so ↓ :

````markdown
```card
type: pullquote
text: Your not gonna be picking a fight, Dad, dad dad daddy-o.
position: right
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

The system automatically finds a reasonable place for the pullquote but if you want to control exactly where it is in the paragraph, you can indicate this with 2 pipes like so: `||` and that will indicate where the break for the pullquote goes. Like so ↓ :

````markdown
```card
type: pullquote
text: Your not gonna be picking a fight, Dad, dad dad daddy-o.
position: right
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. || There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

↑ And that looks like this ↓ :

---

```card
type: pullquote
text: Your not gonna be picking a fight, Dad, dad dad daddy-o.
position: right
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. || There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

## Post Link

Post links are a great way to link to other posts in your site with support for thumbnails. The syntax is easy and automatically imports the necessary info and image.

````markdown
```card
type: post-link
style: small
post: collection-full
```
````

↑ That code will produce this ↓ :

```card
type: post-link
style: small
post: collection-full
```

### Options

<mark>Note:</mark> Most of these are not required. You can just use: `type:`, `post:`, these are here if you want to customize. As long as you add a `post:` option, it will pull all the info from the post. But you can override that if you like.

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `post-link` |
| `post` | Yes | Reference a post by its url_name — auto-populates all fields |
| `style` | No | `small` (default), `medium`, or `large` |
| `title` | No | Override or provide custom title |
| `subtitle` | No | Override subtitle (medium/large only) |
| `excerpt` | No | Override excerpt (medium/large only) |
| `image` | No | Override image path, or set to `none` to hide image |
| `author` | No | Override author — falls back to site author |
| `date` | No | Override date |
| `url` | No | Custom URL if not using `post` reference |
| `link_text` | No | Custom call-to-action text — defaults to "Read more →" |

### Examples

````markdown
```card
type: post-link
style: small
post: collection-full
```
````

↑ That code will produce this ↓ :

```card
type: post-link
style: small
post: collection-full
```

And you can change the size (small/medium/large)

````markdown
```card
type: post-link
style: medium
post: collection-full
```
````

↑ That code will produce this ↓ :

```card
type: post-link
style: medium
post: collection-full
```

This simple syntax will pull all the information from the Post itself. You can also override this fully if you want. Just add the fields you'd like to replace ↓ :

````markdown
```card
type: post-link
post: collection-full
style: large
title: Collection Full
author: Benjamin Welch, Esq.
date: 1983-06-15
excerpt: Example of full collection
link_text: Read more…
```
````

↑ Above will look like this ↓ :

```card
type: post-link
post: collection-full
style: large
title: Collection Full
author: Benjamin Welch, Esq.
date: 1983-06-15
excerpt: Example of full collection
link_text: Read more…
```

<mark>Note:</mark> when you add `style: small`, `style: mediuam` or `style: large` this adds a CSS class to the element so that you can style it however you like. You could use `style: featured` if you like and use CSS to style the `post-link-featured` card.

## Aside

Asides allow you to add notes "next to" the content of the text. The syntax is similar to other cards. You can create an Aside with: just [text](#just-text), [image](#just-image), [both](#both). You can also add [links](#and-an-aside-can-use-links)

### Options

Add an image, some text, or both, and point the whole card somewhere with `link_url:` if you'd like to.

`text:` had full markdown support. It will grab everything between: `text:` and the next option such as `image:` or the closing backticks. See examples below.

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `aside` |
| `text` | No | Body text, written in Markdown. Several paragraphs are fine |
| `image` | No | Path to image — displays above text |
| `link_url` | No | Makes the whole aside a link, image included |

### Just Text (example)

<mark>Note: the aside will be next to the paragraph immediately below it:</mark>

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future.
````

↑ This code looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future.

---

↑ <mark>Try different browser widths to see how it interacts</mark>

### Just Image (example)

````markdown
```card
type: aside
image: /media/images/old_plane.jpg
```

You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o.
````

↑ This code looks like this ↓ :

---

```card
type: aside
image: /media/images/old_plane.jpg
```

You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o.

---

### Image + Text (example)

You can use both image and text like so ↓ :

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
image: /media/images/old_plane.jpg
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

↑ This code looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
image: /media/images/old_plane.jpg
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

### Asides can use links (example)

There are two ways to link from an aside, and they do different things.

**Write the link in the text.** Because `text:` is Markdown, you choose the wording and where it sits:

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?

[Quoted from Back to the Future →](https://en.wikipedia.org/wiki/Back_to_the_Future)
```
````

**Or point the whole card somewhere** with `link_url:`. The entire aside becomes a link, image included — useful when the aside is a picture, or a short note that's all one destination:

````markdown
```card
type: aside
image: /media/images/old_plane.jpg
text: A short note that all points one way.
link_url: https://en.wikipedia.org/wiki/Back_to_the_Future
```
````

You can't do both at once: a link inside a link isn't valid HTML. If your text already contains a link, `link_url` goes on the image instead, and with no image Roe tells you in the preview that it had nowhere to put it.

↑ The first of those looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?

[Quoted from Back to the Future →](https://en.wikipedia.org/wiki/Back_to_the_Future)
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

## Product Link

<mark>Store only:</mark> Product Link cards need the **Store** feature turned on. If you haven't enabled it yet, go to [Admin → Settings](/admin/configs) and click **Enable Store** — until then, `product-link` won't show up in the `CARD ▼` menu.

A Product Link works just like a [Post Link](#post-link), but points at a product in your store. Add a `product` and the card pulls in its title, price, image, and description automatically — you only fill in what you want to override.

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `product-link` |
| `product` | Yes | Reference a product by its url_name — auto-populates all fields |
| `style` | No | `small` (default), `medium`, or `large` |
| `title` | No | Override the title pulled from the product |
| `description` | No | Override the description pulled from the product |
| `show_description` | No | `true`/`false` — show the product's description (on by default) |
| `url` | No | Override the link target (defaults to the product's page) |
| `link_text` | No | Custom call-to-action — defaults to "View product →" |
| `image` | No | Override the product image, or set to `none` to hide it |

### Example

````markdown
```card
type: product-link
product: blue-tshirt
style: medium
```
````

↑ That pulls the Blue T-shirt's title, price, image, and description into a medium card. Like Post Links, add any field above to override what's pulled in.

## Player

<mark>Music only:</mark> Player cards need the **Music** feature turned on. Until then `player` won't appear in the `CARD ▼` menu.

A Player card puts a single audio player in the middle of your writing — a track you want someone to hear at that point, rather than a whole release.

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `type` | Yes | Must be `player` |
| `audio` | Yes | Path to the audio file |
| `title` | No | Shown beside the player |
| `image` | No | Artwork to show with it |
| `show_artwork` | No | `false` hides the artwork |

````markdown
```card
type: player
audio: /media/audio/the-quiet-hours-03.mp3
title: Three — The Quiet Hours
image: /media/images/quiet-hours.jpg
```
````

For a whole release, use the [`playlist` collection template](/documentation/roe/collections_templates#when-to-use-the-playlist-template) instead — it gives you one player and a track list rather than a player per track.

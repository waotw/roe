---
roe_version: 0.0.9
title: Cards
status: published
---

# Cards

Cards use a similar syntax to Collections and allow you to embed styled elements directly in a markdown file: [pullquote](#pull-quote), [post link](#post-link), [aside](#aside).

To keep things simple, each card `type` has it's own defaults. The card defaults can be edited in [Admin/Settings](/admin/configs/cards/edit).

Use the `CARD ▼` button in the editor to insert a card. The `CARD ▼` button templates can be edited as well: [Admin/Settings](/admin/configs/cards/edit).

## Pull quote

Markdown supports block quotes but not pull quotes. Cards allows you to add them easily.

````markdown 
```card
type: pullquote
text: There's only one way to find out…
```
````

↑ This code will look like this ↓ :

---

```card
type: pullquote
text: There's only one way to find out…
```

---

You can also add `attribution` if this quote is from someone specific:

````markdown 
```card
type: pullquote
text: There's only one way to find out…
attribution: great philosopher
```
````
↑ Above looks like this ↓ :

---

```card
type: pullquote
text: There's only one way to find out…
attribution: great philosopher
```

---

### position
(default: `center`)

You can also use a `position` parameter: `left`, `right`, `center`. This allows the pullquote to be amount the text and have the text flow around it. Like this:

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

Post links are a great way to link to other posts in your site with support for thumbnails. The syntax is this easy and automatically imports the necessary info and image:

````markdown
```card
type: post-link
style: small
post: the-literary-wasteland-1
```
````

↑ That code will produce this ↓ :

```card
type: post-link
style: small
post: the-literary-wasteland-1
```

This simple syntax will pull all the information from the Post itself. You can also override this fully if you want. Just add the fields you'd like to replace ↓ :

````markdown
```card
type: post-link
post: the-literary-wasteland-1
style: large
title: The Literary Wasteland, 1
author: Darren Allen, Esq.
date: 1983-06-15
excerpt: Mediocre Literature is coming for us all.
link_text: Read more…
```
````

↑ Above will look like this ↓ :

```card
type: post-link
post: the-literary-wasteland-1
style: large
title: The Literary Wasteland, 1
author: Darren Allen, Esq.
date: 1983-05-15
excerpt: Mediocre Literature is coming for us all.
link_text: Read more...
```

<mark>Note:</mark> that when you add `style: small` or `style: large` this adds a CSS class to the element so that you can style it however you like. You could use `style: featured` if you like and use CSS to style the `post-link-featured` card.

## Aside

Asides allow you to add notes "next to" the content of the text. The syntax is similar to other cards. You can create an Aside with: just [text](#just-text), [image](#just-image), [both](#both). You can also add [links](#and-an-aside-can-use-links)

### Just Text

<mark>Note: the aside will be next to the paragraph immediately below it:</mark>

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

↑ This code looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

↑ <mark>Try different browser widths to see how it interacts</mark>

### Just Image


````markdown
```card
type: aside
image: /media/images/example-blog-2.jpg
```

You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

↑ This code looks like this ↓ :

---

```card
type: aside
image: /media/images/example-blog-2.jpg
```

You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

### Both

You can use both image and text like so ↓ :

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
image: /media/images/example-blog-2.jpg
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.
````

↑ This code looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
image: /media/images/example-blog-2.jpg
```
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

---

### And an aside can use links

To add a link to an Aside, just do this ↓ :

````markdown
```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
link: https://en.wikipedia.org/wiki/Back_to_the_Future
link_text: Quoted from →
``` 
````

↑ This code looks like this ↓ :

---

```card
type: aside
text: I'll never let him forget it. And if I did, what would that make me?
link: https://en.wikipedia.org/wiki/Back_to_the_Future
link_text: Quoted from →
``` 
You wait and see, Mr. Caruthers, I will be mayor and I'll be the most powerful mayor in the history of Hill Valley, and I'm gonna clean up this town. There's that word again, heavy. Why are things so heavy in the future. Is there a problem with the Earth's gravitational pull? Your not gonna be picking a fight, Dad, dad dad daddy-o. You're coming to a rescue, right? Okay, let's go over the plan again. 8:55, where are you gonna be. Wow, ah Red, you look great. Everything looks great. 1:24, I still got time. Oh my god. No, no not again, c'mon, c'mon. Hey. Libyans. It works, ha ha ha ha, it works. I finally invent something that works.

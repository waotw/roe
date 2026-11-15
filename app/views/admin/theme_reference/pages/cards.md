Every card type: asides, post links and product links. The posts and products they link to are samples: they exist only while this page is drawn, so their links go nowhere.

## Pullquotes

```card
type: pullquote
text: A pull quote in the centre of the text, with an attribution.
attribution: Sample Author
position: center
```

```card
type: pullquote
text: A pull quote positioned on the left.
position: left
```

When a pullquote is positioned on the left, it belongs to the paragraphs below it in the markdown and the text will wrap around it. This one is long enough to show how the text flows next to the quote at larger sizes and then centers at smaller widths. Themes set the quote's size, style and spacing around it, as well as when it switches to center.

```card
type: pullquote
text: A pull quote positioned on the right.
position: right
```

The same again on the other side. Text wraps to the left of the quote and then carries on underneath it. If the paragraph is short, it's best to use `position: center` or make the pullquote much smaller in the theme's CSS.

## Aside: text

```card
type: aside
text: An aside holds a short note beside the main text.

It can run to more than one paragraph, and use **Markdown**.
```

Asides sit beside the paragraph that follows them. This paragraph is here so the aside can sit next to it, the way it would in a post. The CSS of a theme controls what the asides look like, where they sit and when, how narrow or wide they are, etc. The aside will sit to the left of the paragraph on larger screens and sit within the text as the screen gets smaller. Then it will just be centered above the paragraph.

## Aside: image and text

```card
type: aside
image: /admin/themes/reference/media/sample-2.jpg
text: An aside with an image above its text.
```

Asides sit beside the paragraph that follows them. This paragraph is here so the aside can sit next to it, the way it would in a post. The CSS of a theme controls what the asides look like, where they sit and when, how narrow or wide they are, etc. The aside will sit to the left of the paragraph on larger screens and sit within the text as the screen gets smaller. Then it will just be centered above the paragraph.

## Aside: a link

```card
type: aside
image: /admin/themes/reference/media/sample-3.jpg
text: The whole aside is a link.
link_url: #aside-a-link
```

Asides sit beside the paragraph that follows them. This paragraph is here so the aside can sit next to it, the way it would in a post. The CSS of a theme controls what the asides look like, where they sit and when, how narrow or wide they are, etc. The aside will sit to the left of the paragraph on larger screens and sit within the text as the screen gets smaller. Then it will just be centered above the paragraph.

## Post link: small

```card
type: post-link
post: theme-reference-a-week-on-the-coast
style: small
```

## Post link: medium

```card
type: post-link
post: theme-reference-how-the-garden-grew
style: medium
```

## Post link: large

```card
type: post-link
post: theme-reference-letters-i-never-sent
style: large
```

## Product link

```card
type: product-link
product: theme-reference-sample-print
style: medium
```

---
title: Roe-anji → Images & Image Galleries
status: published
url_name: galleries
tags: roe-anji
related:
  - roeanji
---

##### Related documentation

```collection
source: documentation/roe
related: true
limit: all
template: links
```

# Images & Image Galleries

Roe makes it really easy to create image galleries in Posts or Pages with Markdown. All gallery images have a light-box feature automatically (click to enlarge) with a [carousel/slideshow](#carousel-slideshow) options as well.

## Uploading Images

In order to add images to your Post/Pages, you'll need to upload them. There are 2 ways to do this:

### `MEDIA ▼` button in The Editor

Opens a media browser in the editor and you can insert media directly at your cursor.

### [Admin → Media](/admin/medium/browse)

On this page, you can:

- rename the file (double click on the name)
- `COPY URL` - this is gives you the `path` you need to use images in Cards and Settings.
- `MARKDOWN LINK` - this is the exact syntax you need to add that image to a Post/Page.

## Just one image, on it's lonesome

If you want an image on it's own, just use a standard Markdown image:

```markdown
![Image 1](/media/images/photo1.jpg)
```

Use the `MEDIA ▼` button in The Editor to open the media browser and drop an image directly at your cursor.

## Simple Gallery

When you place 2 or more images consecutively (without blank lines between them), they automatically become a gallery:

```markdown
![pet_sounds_-color_corrected.jpg](/media/images/pet_sounds_-color_corrected.jpg)
![Image 2](/media/images/photo2.jpg)
![Image 3](/media/images/photo3.jpg)
```

↑ This creates a 3-column grid like this ↓

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

## Fancy Gallery

By wrapping the images in a `gallery` block, you can:

- control the layout of the images
- feature images
- add captions to individual images
- add a single caption for the whole gallery
- set the aspect ratio of the images
- display them as a carousel/slideshow

````markdown
```gallery
![Image 1](/media/images/photo1.jpg)
```
````

Rather than typing the block out by hand, click the `GALLERY` button in The Editor. It opens a little menu where you can switch on a carousel, choose an aspect ratio, and add a gallery caption — then it drops the finished block in at your cursor with a placeholder ready for your images.

Use the `MEDIA ▼` button in The Editor to add your images where `__PLACEHOLDER__` is.

This allows you to do some fancy things such as…

## Featured/Hero Image

If you want an image to be full-width, just put it on it's own line like so ↓

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
```
````
↑ That will look like this ↓

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
```

- Row 1: 1 image (full width)
- Row 3: 3 images (33% width each)

## Carousel (slideshow)

Instead of a grid, add `slideshow: true` at the bottom of the gallery to make it carousel/slideshow like so ↓

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
slideshow: true
```
````

↑ that will look like this ↓

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
slideshow: true
```

## Captions

Add captions to any image using this syntax `(*caption-here*)` immediately after the image ↓

````markdown
```gallery
![house on ilkley moore](/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```
````

↑ This will produce an image with a caption ↓
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```

## Gallery Caption

The `(*...*)` syntax above captions a single image. To add one caption for the **whole gallery** instead, put a `caption:` line inside the block ↓

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
caption: A weekend on the moor
```
````

↑ That adds a single caption beneath the whole gallery ↓

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
caption: A weekend on the moor
```

You can use both kinds at once — per-image `(*...*)` captions and a gallery `caption:` — in the same block.

## Aspect Ratio

By default, each image takes the shape your theme gives that layout. Add an `aspect_ratio:` line to give every image in the gallery the same shape ↓

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
aspect_ratio: square
```
````

↑ That crops each image to a square ↓

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
aspect_ratio: square
```

The default theme gives you:

- `square` — 1:1
- `portrait` — 3:4
- `tv` — 4:3 (alias: `landscape`)
- `wide` — 16:9
- `cinema` — 21:9 super wide (alias: `film`)
- `original` — keep each image's natural shape (alias: `auto`)

These match the ratios used by [product collections](/documentation/store#displaying-products-with-collections), so the same names work in both places. Which ratios are available comes from your theme's CSS, so a theme can offer its own.

**Note:** aspect ratio doesn't apply to a carousel (`slideshow: true`) — those images are sized by height instead.

## Combine all these features

Let's create a Gallery with 3 rows and captions. We'll have:

- A hero image on top
- 3 images in the middle
- 2 on the bottom
- all with captions

Here is to the code to achieve that:

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```
````

↑ This code will look like this ↓

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```


## Column Limits

Galleries support 1-3 columns per row. If you place more than 3 images on a single row, they will wrap.

## Responsive Behavior

Right now, all gallery layouts are maintained even at small sizes. Room for improvement.

## Spacing

Gallery spacing is controlled by the `--space-gallery` CSS variable in your theme. Set to `0rem` for no gaps between images, or increase for more spacing.

---
roe_version: 0.0.26
title: Images & Image Galleries
status: published
url_name: galleries
---

# Images & Image Galleries

Roe CMS makes it really easy to create image galleries in Posts or Pages with Markdown.

## Uploading Images

In order to add images to your Post/Pages, you'll need to upload them. There is a link in the Admin for Media which will bring you to the Media Manager. On this page, you can:

- rename the file (double click on the name)
- `COPY URL` - this is gives you the `path` you need to use images in Cards and Settings.
- `MARKDOWN LINK` - this is the exact syntax you need to add that image to a Post/Page.

You can also access the Media page while editing a Post/Page. This will open it up in a new tab so you can upload an image or grab the link you need, then paste it in your Markdown.

## Just one image, on it's lonesome

If you want an image on it's own, just use a standard Markdown image:

```markdown
![Image 1](/media/images/photo1.jpg)
```

Copy the `MARKDOWN LINK` from the Media Manager as outlined [above](#uploading-images).

## Simple Gallery

When you place 2 or more images consecutively (without blank lines between them), they automatically become a gallery:

```markdown
![Image 1](/media/images/photo1.jpg)
![Image 2](/media/images/photo2.jpg)
![Image 3](/media/images/photo3.jpg)
```

↑ This creates a 3-column grid like this ↓ :

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

## Fancy Gallery

By wrapping the images in a `gallery` block, you can:

- control the layout of the images
- feature images
- add captions to images

````markdown
```gallery
![Image 1](/media/images/photo1.jpg)
```
````

This allows you to do some fancy things such as…

## Featured/Hero Image

If you want an image to be full-width, just put it on it's own line like so ↓ :

````markdown
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
```
````
↑ That will look like this ↓ :

```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)

![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)
```
- Row 1: 1 image (full width)
- Row 3: 3 images (33% width each)

## Captions

Add captions to any image using this syntax immediately after the image ↓ :

````markdown
```gallery
![house on ilkley moore](/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```
````

↑ This will produce an image with a caption ↓ :
```gallery
![house on ilkley moore](/media/images/house-on-ilkley-moore.jpg)(*House on Ilkley Moore*)
```

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

↑ This code will look like this ↓ :

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

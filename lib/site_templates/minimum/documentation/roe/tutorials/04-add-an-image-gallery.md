---
title: 4) How to Add an Image Gallery
status: published
tags: tutorial
related:
  - 5-how-to-add-a-collection
---

#### Previous Tutorial
```collection
source: documentation/roe
related: true
limit: 1
offset: 1
template: links
```

# How to add an image gallery

You created a simple gallery in the last tutorial by adding this:

```markdown
![The Apartment Pixel Art](/media/images/apt-pixel-art.png)
![Old plane in a hangar](/media/images/old-plain.jpg)
![Old barn](/media/images/old-barn.jpg)
```

## How to add a Fancy Gallery

1. In the editor, select the 3 images you added and click the `GALLERY` button.
2. Select `Display as carousel?`
3. Click `INSERT`
4. This will wrap the simple gallery in a code block like this:
    ````markdown
    ```gallery
    ![The Apartment Pixel Art](/media/images/apt-pixel-art.png)
    ![Old plane in a hangar](/media/images/old-plain.jpg)
    ![Old barn](/media/images/old-barn.jpg)
    slideshow: true
    ```
    The above is an example, you'll upload your own images.
    ````
5. Check the preview and you'll see your gallery is now a carousel/slideshow.

You now know how to create galleries. Galleries also allow you to change sizing and layout, as well as add captions. Learn all about Galleries here: [Galleries](/documentation/roe/galleries)

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

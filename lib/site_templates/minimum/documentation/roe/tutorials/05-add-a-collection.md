---
title: 5) How to Add a Collection
status: published
tags: tutorial
related:
  - 6-how-to-create-a-post
---

#### Previous Tutorial
```collection
source: documentation/roe
related: true
limit: 1
offset: 1
template: links
```

# How to add a Collection

## Why you should understand and use Collections

A very simple website often consists of a few pages with some text and images. What if you want to add a blog or a podcast? Collections do exactly that. A Collection displays a list of content in Roe such as a list of blog posts or podcast episodes. Collections allow you to add these lists anywhere in your site.

## Add a Collection

1. In the editor, click the `COLLECTION` button and you'll see a form.
2. Add `All posts` to the heading section and click `INSERT`.
3. You will see a block like this:
    ````markdown
    ```collection
    heading: All posts
    source: posts
    post_type: all
    template: list
    limit: 5
    ```
    ````
    - This Collection shows your `posts` under the heading `All posts`.
4. Check the preview and you'll see a list of all the posts you have. Right now it's probably just the welcome post, unless you created your own.
5. In the collection, change `template: list` to `template: compact` and check the preview to see how it changes what the collection renders.
6. Let's create a new post in the next tutorial and you'll see it show up in this Collection.

##### Next tutorial
```collection
source: documentation/roe
related: true
limit: 1
template: links
```

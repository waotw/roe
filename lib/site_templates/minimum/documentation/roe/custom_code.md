---
title: Custom Code
status: published
---

# Custom Code

Being able to add your own JavaScript and CSS is an important feature for any CMS. Useful for analytics, fonts, third-party widgets, and other code you'd normally add to a site's `<head>` or just before the closing `</body>`.

> ⚠︎ How this works  
> Only paste code from sources you trust. Hostnames referenced in `src=` / `href=` attributes automatically added to the CSP(Content Security Policy) - you don't need to add this yourself.

### Scripts in the Header

Header scripts run **only on initial page load**, so any `<script>` you put in the header section runs once and never again for the visitor's session.

### Scripts in the Footer

Footer scripts run **every time a visitor lands on a page**, you don't have to do anything special — scripts that initialize on every page load Just Work.

## JavaScript

Opening and closing `<script>` tags are required.

### Inline

```html
<script>
  // your code
</script>
```

### External file

```html
<script src="https://example.com/file.js"></script>
```

## CSS

Opening and closing `<style>` tags are required.

### Inline

```html
<style>
  .my-class { color: red; }
</style>
```

### External file

```html
<link rel="stylesheet" href="https://example.com/file.css">
```

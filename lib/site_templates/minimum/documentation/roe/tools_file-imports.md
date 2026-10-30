---
title: File Imports
status: published
tags: tool
---

# Importing a site from files

This tool is in the Admin under: 🛠️ → [Feed Imports](/admin/file_imports/).

Roe can import an HTML site. It will do it's best to categorize which files are pages or posts.

## How to import files

1. Upload a zip file of your site.
2. Click `UPLOAD & REVIEW`
3. Choose what should be a Post, Page and what to skip (Podcasts are better imported via feed)
4. If Navigation is detected, choose where you'd like the navigation to go.
  - Your header.md or sidebar.md will still exist. They'll be saved to `header.replaced.md` and `sidebar.replaced.md` in the `site/layout/` folder.
5. Review what will be imported
6. Choose to import all bundled media.
  - If the site folder contains any media, it will import it into your `site/` folder.
7. Click `IMPORT AS DRAFTS`

This will import the posts and pages. If you would like Roe to download any media that is external (Cloudflare, CDN, another host) you can use the [Media Imports](/admin/media_imports/) tool. It automatically detects external references and offers to import them into your `site/` folder.

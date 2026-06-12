---
roe_version: 0.0.9
title: File first approach
status: published
---

# File-first approach

This system operates on a file-first architecture. Your content exists as markdown files in the `content/` directory. The database serves as a cache layer for performance, but the markdown files are the canonical source of truth.

The admin interface is an editor for these files. You can edit files directly in a text editor or through the admin—both methods work identically. When you save through the admin, it writes to the markdown file. When you edit the files directly, the system watches for changes and syncs them to the database automatically.

This architecture ensures portability: your content is never locked into a proprietary format.

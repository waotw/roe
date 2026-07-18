---
title: Themes
status: published
tags: admin
---

# Themes

A theme controls how your site looks — its colors, fonts, spacing, and layout. Each theme is a single CSS file with a set of variables at the top for the changes you'll make most often. Adjust those variables to restyle your site in seconds, or edit the CSS directly when you want full control.

<mark>Note: custom fonts are handled separately, under Settings → Fonts.</mark>

## How themes work

**Built-in themes.** Roe ships with a curated set of themes. Preview any of them before you commit. When you activate a theme, Roe makes it live and copies its file into your site's theme folder, where you can edit it. Change your active theme anytime under Settings → Site → Theme.

**Editing.** Every theme is just a file. Edit it live in Roe (Admin → Themes → `EDIT CSS`), or open the file in any text editor and save. Your edits stick when you switch between themes.

**Reverting.** Changed a built-in theme and want the original back? Open `EDIT CSS` and click the revert button. Roe restores the bundled version.

**Updates.** When Roe updates, its built-in themes may improve. Roe tracks each theme's version separately from your copy, so when a newer version exists, you'll see an update option. Roe never overwrites your active theme on its own — you decide when, or whether, to apply an update.

## Preview your changes as you edit

When you edit a theme's CSS in Roe, you don't have to save to see the result. Roe applies your changes to a live preview as you type.

To set it up:

1. Open Admin → Themes and click `EDIT CSS` on the theme you want to change.
2. Click `Preview`.
   Roe opens your site in a new browser tab.
3. Arrange the editor and the preview side by side.
4. Edit the CSS.
   The preview updates as you type — no save needed.
5. Save when you're happy with it.
   The preview reloads with your saved file.

For best results, size the two windows so the editor sits on one side and the preview on the other. That way every change lands in front of you, and you can tune a color or a spacing value until it looks right.

## Customizing a theme

The fastest way to restyle your site is through the **CSS variables** at the top of the theme file. They set colors, spacing, fonts, and layout in one place, so you can make sweeping changes without touching the rest of the CSS. The rest of this page lists those variables. You're free to edit the full file too — see [Going further](#going-further).

## CSS variables

### Layout

`--container-width` = The maximum width of the overall site container.

`--sidebar-width` = Width of the optional site [sidebar](layouts#sidebar) (left or right). <mark>Note: add a sidebar in Layouts → Sidebar and create the file.</mark>

`--aside-width` = When an [aside](cards#aside) is present, the main content shifts right by this amount and the aside sits in the space that opens up.

#### Fine-tuning asides

```css
--aside-text-top-offset: 0.25rem;
--aside-image-top-offset: 0.4rem;
```
These two variables align the top of an aside with the first line of the body text beside it. Different fonts have different line metrics, so a small offset keeps the two visually level. Adjust them if you change fonts and notice an aside sitting slightly high or low.

### Typography

`--font-scale` = Increase or decrease this to scale every font size on the site at once.

**Font families.** Headings and accent text use the body font by default. Set `--font-heading` or `--font-accent` to give those elements a different typeface.

```css
--font-body: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
--font-heading: var(--font-body);
--font-accent: var(--font-body);
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, "Courier New", monospace;
```

### Font sizes

```css
--text-xxs: 0.7rem;
--text-xs: 0.8rem;
--text-sm: 0.875rem;
--text-base: 1rem;
--text-lg: 1.125rem;
--text-xl: 1.25rem;
--text-2xl: 1.5rem;
--text-3xl: 1.75rem;
--text-4xl: 2.25rem;
--text-5xl: 3rem;
```

### Spacing

A single scale for the margins, padding, and gaps used throughout the theme.

```css
--space-0: 0;
--space-1: 0.25rem;
--space-2: 0.5rem;
--space-3: 0.75rem;
--space-4: 1rem;
--space-6: 1.5rem;
--space-7: 1.75rem;
--space-8: 2rem;
--space-12: 3rem;
--space-16: 4rem;
```

`--space-gallery` = The gap between images in a [gallery](galleries). Lower it for tighter photos, raise it for more breathing room.

### Colors

```css
--color-bg: #ffffff;
--color-bg-dim: #f5f5f5;
--color-text: #000000;
--color-heading: #000000;
--color-logo: #000000;
--color-nav-active: #000000;
--color-muted: #666666;
--color-link: #0000ee;
--color-visited: #0000ee;
--color-link-collection: #000000;
--color-border: #e3e3e3;
--color-code-bg: #f5f5f5;
--color-code-text: #000000;
--color-highlight-text: #ffff00;
```

Most of these explain themselves. A few worth calling out:

- `--color-link` sets normal link color and `--color-visited` sets visited links. Give them the same value if you don't want visited links to look different.
- `--color-link-collection` colors links inside [collections](collections) (posts, pages, products), so you can style them apart from regular text links.
- `--color-bg-dim` shades subtle areas like alternating table rows and form fields.
- `--color-highlight-text` sets the background behind highlighted text.

### Media players

Colors and backgrounds for the audio and video players. They're scoped on their own, so you can give the players a look distinct from the rest of the page.

```css
--player-bg: #f5f5f5;
--player-border: #dddddd;
--player-track: #cccccc;
--player-accent: #333333;
--player-accent-hover: #000000;
--player-btn-color: #333333;
--player-btn-play-color: #ffffff;
--player-btn-hover-bg: rgba(0, 0, 0, 0.07);
--player-meta-color: #888888;
--player-overlay-bg: rgba(255, 255, 255, 0.75);
--player-chapter-active-bg: rgba(0, 0, 0, 0.05);
```

## Going further

When the variables aren't enough, edit the full CSS file for a completely custom theme. The class names are semantic, and many are documented in the CSS itself. If a change goes sideways, revert to the original at any time from Admin → Themes → `EDIT CSS`.

If you get stuck or want to share your work:

- [Email support](mailto:roe@weareontheweb.com) and a human will get back to you.
- File an issue if you've found a bug.
- Send a pull request if you've improved a built-in theme or built one others could use.

---
roe_version: 0.0.9
title: Themes
status: published
---

# Themes

Roe's theme system works with one CSS file. There are variables at the top to make it easy to change typography, spacing, colors, etc. And you can edit the CSS file any way you like or create your own theme.

<mark>Note: custom fonts are handled in the system settings: Settings → Fonts.</mark>

## How the theme system works

**Built-in themes** — Roe comes with a curated set of themes. You can preview any theme before activating it. Activating a theme makes it live and copies the file to your site's theme folder. You can always change the theme under: Settings → Site → Theme.

**Reverting** — If you edit a theme's CSS and want to go back, you can revert to the original built-in version at any time. Just click `EDIT CSS` and you'll see a button to revert. 

**Version tracking** — When Roe updates, built-in themes may improve. Roe tracks the version of each theme independently from your site. If a newer version of a theme is available, you'll see an update option. Importantly, Roe will never overwrite your active theme automatically — you choose when (or if) to apply the update.

**Custom themes** — You're also free to edit the CSS directly. Every theme is just a file. Open it in any text editor, make changes, and save. Or edit the CSS live in the theme section of Roe. Your edits are preserved when switching between themes.

## Customizing a theme

Every theme uses **CSS variables** at the top of the file. This is the easiest and fastest way to customize colors, spacing, fonts, and layout without getting into the nitty gritty but you can do that too.

## CSS Variables

### Layout

`--container-width` = The maximum width of the overall site container.

`--sidebar-width` = Width of the optional site [sidebar](layouts#sidebar) (left or right). <mark>Note: Add a sidebar in Layouts → Sidebar and create the file.</mark>

`--aside-width` = When an [aside](cards#aside) is present, the main content shifts right by this amount and the aside is positioned in this space.

#### Fine-tuning asides

```css
--aside-text-top-offset: 0.25rem;
--aside-image-top-offset: 0.4rem;
```
These two variables fine-tune the vertical alignment between the aside and the text to the right of it. Different fonts have different line metrics, so these small offsets ensure the top of the aside and the first line of body text appear visually aligned. Adjust these if you change fonts and notice a slight misalignment with asides.

### Typography

`--font-scale` = Increase/decrease to affect all font-sizes across the site.

**Font families**  
By default headings and accent text inherit from the body font. Change `--font-heading` or `--font-accent` to use a different typeface for those elements.

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

Consistent spacing scale used for margins, padding, and gaps throughout the theme.

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

`--space-gallery` = the gab between images in a [gallery](galleries). Adjust this if you want tighter or looser spacing between gallery photos.

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

Most of these are self-explanatory, but a few notes:

- `--color-link` controls normal link color; `--color-visited` controls visited links. Set them to the same value if you don't want visited-state differentiation.
- `--color-link-collection` is used for links inside [collections](collections) (posts, pages, products), letting you style collection links separately from text links.
- `--color-bg-dim` is used for subtle shaded areas like alternating table rows or form field backgrounds.
- `--color-highlight-text` sets the background color for highlighted text.

### Media players

Colors and backgrounds for the audio and video players. These are scoped separately so you can give the players a distinct look from the rest of the page.

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

You're welcome to edit the entire CSS file as well for a fully custom theme. The class names are all semantic and many are documented in the CSS itself. If you run into trouble, you can always revert back to the original CSS for any theme from `Admin → Themes → Edit CSS`.

- Send an [email to support](mailto:roe@weareontheweb.com) and a human will get back to you
- File an issue here if you've found a bug
- If you've made improvements to any built-in theme or want to create a theme that others can use, feel free to file a pull request.

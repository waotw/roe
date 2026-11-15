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

**Reverting.** Changed a built-in theme and want the original back? Open `EDIT CSS` and click `RESET TO ORIGINAL`. Roe restores the bundled version.

**Updates.** When Roe updates, its built-in themes may improve. Roe tracks each theme's version separately from your copy, so when a newer version exists, you'll see an update option. Roe never overwrites your active theme on its own — you decide when, or whether, to apply an update.

## The theme editor

Admin → Themes → `EDIT CSS` opens the editor: the sections of the theme on the left, its CSS in the middle and your site on the right.

**Preview.** The preview shows your changes as you type, before you save. It opens on the page you last looked at, or the first reference page. Links in it work, so you can go to any page of your site. The menu above it jumps to a reference page, the home page or a path you type. `WIDE` and `PHONE` set its width. In a narrow window the preview is hidden until you click `PREVIEW`.

**Sections.** The list on the left has one entry per section heading in the CSS (see [Sections](#sections)), plus the subsections of the section you're in. Click one to go to it. `HIDE ‹` folds the list into a strip on the left edge; hover the strip to see the list, and click it or `KEEP OPEN` to bring it back for good.

**INSPECT.** Click `INSPECT`, then click anything in the preview. The editor lists every rule in the theme that styles it, in the order they appear in the file, and highlights them in the CSS. `PREV` and `NEXT` step through them.

- A rule that applies only on hover or focus, or to `::before` and `::after`, is labelled.
- A rule inside an `@media` block that doesn't match the preview right now, such as a phone-only rule in a wide preview, is greyed out.
- Click a variable, such as `--font-mono → THEME VARIABLES, line 38`, to go to where it's set. Change it there to change it everywhere it's used.
- **Inherited from** lists the text settings, such as color and font, that the element takes from the elements around it.
- The path at the top shows where the element sits on the page. Click a step to inspect that element instead.

`INSPECT` stays on until you click `INSPECTING` or press Escape.

**Saving.** `SAVE`, or ⌘S / Ctrl+S, saves without leaving the page. Undo keeps working after you save. `FIND & REPLACE`, or ⌘F / Ctrl+F, searches the CSS.

**SAVE AS…** saves what's in the editor as a new theme, next to the one you're editing, and opens it. Give it a name, such as Default Dark, and Roe writes `default-dark.css`. The theme you started from stays as it was last saved. The new theme is yours: Roe never updates it. It isn't used on your site until you click `ACTIVATE` on the Themes page.

## See every element a theme styles

The theme reference pages show everything a theme can style, on pages drawn the way your site draws its own: text, images and galleries, players, cards and collections, buttons, forms and the store. Use them to check a theme before you make it active, or to see what a change to the CSS touched.

Open them from Admin → Themes → `REFERENCE` on any installed theme. The bar at the top has one tab per page, a theme menu that shows the same page in another installed theme, and `EDIT CSS`. Picking a theme there doesn't make it active.

Only you can see these pages: they need you to be signed in, and they're never part of your site's navigation, search or sitemap.

The posts, products and media on these pages are samples that ship with Roe. They aren't added to your site, so their links go nowhere. Forms and buttons look real but do nothing here. Members, payments and store forms show even when those features are off, so a theme can be ready before you turn them on.

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

Colors for the player's times and a podcast's subscribe buttons. The rest of the player takes the page's own text and border colors.

```css
--player-border: #dddddd;
--player-btn-color: #333333;
--player-btn-hover-bg: rgba(0, 0, 0, 0.07);
--player-meta-color: #888888;
```

## Going further

When the variables aren't enough, edit the full CSS file for a completely custom theme. The class names are semantic, and many are documented in the CSS itself. If a change goes sideways, revert to the original at any time from Admin → Themes → `EDIT CSS`.

### Sections

The themes Roe ships are split into sections in the order things appear on a page: theme variables, the layout (nav, search, sidebar, footer), the content, then collections, galleries, cards, players, buttons and forms, then features such as the podcast, members and the store. Your own CSS goes in `CUSTOM CODE`, the last section.

Each section starts with a heading on one line, in capitals:

```css
/* ==== CARDS ==== */
```

Larger sections are split into subsections:

```css
/* ---- Card: aside ---- */
```

Write a heading exactly this way and it shows up in the theme editor's list of sections. You can add, rename, remove or reorder sections in your own theme.

If you get stuck or want to share your work:

- [Email support](mailto:roe@weareontheweb.com) and a human will get back to you.
- File an issue if you've found a bug.
- Send a pull request if you've improved a built-in theme or built one others could use.

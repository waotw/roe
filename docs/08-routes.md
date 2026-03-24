# Routes

Complete reference of all application routes.

## Public Routes

### Content

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /` | `PagesController#home` | Home page |
| `GET /:slug` | `PagesController#show` | Static pages |
| `GET /posts` | `CollectionsController#posts` | All posts archive |
| `GET /posts/:year/:month/:day/:slug` | `PostsController#show` | Dated post URL |
| `GET /posts/:slug` | `PostsController#show` | Post by slug |
| `GET /documentation/:slug` | `DocumentationController#show` | Documentation page |
| `GET /search` | `SearchController#index` | Content search |

### Collections

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /collections` | `CollectionsController#index` | Base collections |
| `GET /collections/*filters` | `CollectionsController#show` | Filtered collection |

**Filter formats:**
- `tag-{tag}` — Filter by tag
- `{tag1},{tag2}` — Multiple tags (OR)
- `type-{post_type}` — Filter by post type
- `page-{n}` — Pagination
- `{filter}/{template}` — Custom template

### Feeds

| Route | Controller | Format | Description |
|-------|------------|--------|-------------|
| `GET /feed.rss` | `FeedsController#rss` | RSS 2.0 | RSS feed |
| `GET /feed.atom` | `FeedsController#atom` | Atom 1.0 | Atom feed |

### Assets

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /fonts/*path` | `FontsController#show` | Serve custom fonts |

---

## Admin Routes

### Prefix: `/admin`

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin` | `Admin::DashboardController#index` | Dashboard |
| `GET /admin/posts` | `Admin::PostsController#index` | All posts |
| `GET /admin/posts/drafts` | `Admin::PostsController#drafts` | Draft posts |
| `GET /admin/posts/unlisted` | `Admin::PostsController#unlisted` | Unlisted posts |
| `GET /admin/posts/new` | `Admin::PostsController#new` | Create post |
| `POST /admin/posts` | `Admin::PostsController#create` | Create post |
| `GET /admin/posts/:id/edit` | `Admin::PostsController#edit` | Edit post |
| `PATCH /admin/posts/:id` | `Admin::PostsController#update` | Update post |
| `DELETE /admin/posts/:id` | `Admin::PostsController#destroy` | Delete post |
| `GET /admin/posts/:id/preview` | `Admin::PostsController#preview` | Preview post |
| `GET /admin/posts/:id/rename` | `Admin::PostsController#rename` | Rename post form |
| `POST /admin/posts/:id/rename` | `Admin::PostsController#do_rename` | Execute rename |
| `GET /admin/posts/search` | `Admin::PostsController#search` | Post search (AJAX) |
| `GET /admin/pages` | `Admin::PagesController#index` | All pages |
| `GET /admin/pages/new` | `Admin::PagesController#new` | Create page |
| `POST /admin/pages` | `Admin::PagesController#create` | Create page |
| `GET /admin/pages/:id/edit` | `Admin::PagesController#edit` | Edit page |
| `PATCH /admin/pages/:id` | `Admin::PagesController#update` | Update page |
| `DELETE /admin/pages/:id` | `Admin::PagesController#destroy` | Delete page |
| `GET /admin/pages/search` | `Admin::PagesController#search` | Page search (AJAX) |
| `GET /admin/documentation` | `Admin::DocumentationController#index` | All docs |
| `GET /admin/documentation/new` | `Admin::DocumentationController#new` | Create doc |
| `POST /admin/documentation` | `Admin::DocumentationController#create` | Create doc |
| `GET /admin/documentation/:id/edit` | `Admin::DocumentationController#edit` | Edit doc |
| `PATCH /admin/documentation/:id` | `Admin::DocumentationController#update` | Update doc |
| `DELETE /admin/documentation/:id` | `Admin::DocumentationController#destroy` | Delete doc |

### Admin: Media

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/medium` | `Admin::MediumController#index` | Media browser |
| `GET /admin/medium/browse` | `Admin::MediumController#browse` | Browse media |
| `POST /admin/medium/upload` | `Admin::MediumController#upload` | Upload media |
| `GET /admin/medium/search` | `Admin::MediumController#search` | Search media |
| `DELETE /admin/medium/:id` | `Admin::MediumController#destroy` | Delete media |

### Admin: Configuration

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/configs` | `Admin::ConfigsController#index` | Config index |
| `GET /admin/configs/site/edit` | `Admin::ConfigsController#edit_site` | Edit site.yml |
| `PATCH /admin/configs/site` | `Admin::ConfigsController#update_site` | Update site.yml |
| `GET /admin/configs/cards/edit` | `Admin::ConfigsController#edit_cards` | Edit cards.yml |
| `PATCH /admin/configs/cards` | `Admin::ConfigsController#update_cards` | Update cards.yml |
| `GET /admin/configs/collections/edit` | `Admin::ConfigsController#edit_collections` | Edit collections.yml |
| `PATCH /admin/configs/collections` | `Admin::ConfigsController#update_collections` | Update collections.yml |

### Admin: Layouts

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/layouts` | `Admin::LayoutsController#index` | Layout index |
| `GET /admin/layouts/navigation/edit` | `Admin::LayoutsController#edit_navigation` | Edit navigation |
| `PATCH /admin/layouts/navigation` | `Admin::LayoutsController#update_navigation` | Update navigation |
| `GET /admin/layouts/footer/edit` | `Admin::LayoutsController#edit_footer` | Edit footer |
| `PATCH /admin/layouts/footer` | `Admin::LayoutsController#update_footer` | Update footer |

### Admin: Settings

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/settings` | `Admin::SettingsController#index` | Settings index |
| `GET /admin/settings/post_template/edit` | `Admin::SettingsController#edit_post_template` | Edit post template |
| `PATCH /admin/settings/post_template` | `Admin::SettingsController#update_post_template` | Update post template |

### Admin: Static Site

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/static_site` | `Admin::StaticSiteController#index` | Static site status |
| `POST /admin/static_site/generate` | `Admin::StaticSiteController#generate` | Generate static site |

### Admin: Authentication

| Route | Controller | Description |
|-------|------------|-------------|
| `GET /admin/login` | `Admin::SessionsController#new` | Login form |
| `POST /admin/login` | `Admin::SessionsController#create` | Login |
| `DELETE /admin/logout` | `Admin::SessionsController#destroy` | Logout |

---

## Route Constraints

### Admin Authentication

All `/admin/*` routes require authentication via `AuthenticateAdmin` constraint.

### Static Files

In production, requests are served from `public/` if files exist.

---

## Related

- [Admin UI](./07-admin-ui.md) - Using the admin interface
- [Static Generation](./05-sync-generation.md) - Static output structure

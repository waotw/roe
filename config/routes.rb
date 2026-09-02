Rails.application.routes.draw do
  # Block database file access
  constraints(->(req) { req.path =~ /^\/db\// }) do
    match "*path", to: proc { [ 404, {}, [ "Not Found" ] ] }, via: :all
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Machine-to-machine API (token-authed, no admin session). Lives
  # outside the /admin namespace because it's our own Rails app
  # talking to itself across environments — no logged-in user, just
  # a bearer token.
  namespace :api do
    namespace :site_sync do
      post "exchange",                  to: "exchange#create"
      post "refresh_ledger",            to: "exchange#refresh_ledger"
      post "reconcile_content",         to: "exchange#reconcile_content"
      post "file_states",               to: "exchange#file_states"
      post "file_hashes",               to: "exchange#file_hashes"
      get "manifest",                   to: "exchange#manifest"
      post "download",                  to: "exchange#download"
      post "upload",                    to: "exchange#upload"
      post "database",                  to: "exchange#database"
      post "publish_members",           to: "imports#publish_members"
      post "publish_newsletter_sends",  to: "imports#publish_newsletter_sends"
    end
  end

  # Authentication (specific routes first)
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token
  # Lockout recovery via recovery codes — no email dependency, unlike
  # the PasswordsController flow. Used when the admin has lost the
  # password AND can't (or doesn't want to) rely on email reset.
  resources :recovery_codes, only: [ :new, :create ], path: "recovery"

  # Admin area (specific routes before catch-all)
  namespace :admin do
    root "dashboard#index"

    # Updates & Deploy
    get  "updates",                   to: "updates#index",          as: "updates"
    post "updates/check",             to: "updates#check",          as: "check_updates"
    post "updates/start",             to: "updates#start",          as: "start_update"
    post "updates/confirm_ruby",      to: "updates#confirm_ruby",   as: "confirm_ruby_update"
    post "updates/cancel_ruby",       to: "updates#cancel_ruby",    as: "cancel_ruby_update"
    post "updates/rollback",          to: "updates#rollback",       as: "rollback_update"
    get  "updates/status",            to: "updates#status",         as: "update_status"
    post "updates/deploy",                  to: "updates#start_deploy",          as: "start_deploy"
    get  "updates/deploy/status",           to: "updates#deploy_status",         as: "deploy_status"
    post "updates/deploy/dismiss",          to: "updates#dismiss_deploy",        as: "dismiss_deploy"
    post "updates/deploy/reset_and_retry",  to: "updates#reset_and_retry_deploy", as: "reset_and_retry_deploy"
    get  "updates/git_status",        to: "updates#git_status",     as: "git_status"
    post "updates/channel",           to: "updates#update_channel", as: "update_channel"

    # Dependencies — optional external tools (libvips, …): status + the
    # OS-correct install command. Read-only; installs happen in a terminal.
    get "dependencies", to: "dependencies#index", as: "dependencies"

    # Markdown diagnostics for the editor. Shared by posts/pages/products/emails
    # — they all render shared/_editor. POST because the content being checked
    # is in the body (it hasn't been saved yet).
    post "markdown/check", to: "markdown#check", as: "check_markdown"
    post "markdown/fix",   to: "markdown#fix",   as: "fix_markdown"

    # Site Sync
    get "site_sync", to: "site_sync#index", as: "site_sync"
    post "pages/repair_statuses", to: "pages#repair_statuses", as: "repair_page_statuses"
    get "site_sync/history", to: "site_sync#history", as: "site_sync_history"
    post "site_sync/history/restore", to: "site_sync#restore_from_history", as: "restore_from_site_sync_history"
    post "site_sync/backup", to: "site_sync#create_backup", as: "create_site_backup"
    post "site_sync/restore", to: "site_sync#restore_backup", as: "restore_site_backup"
    patch "site_sync/config", to: "site_sync#update_config", as: "update_site_sync_config"
    patch "site_sync/backup_passphrase", to: "site_sync#update_backup_passphrase", as: "update_site_sync_backup_passphrase"
    post  "site_sync/backups/decrypt_db",  to: "site_sync#decrypt_backup_database",  as: "decrypt_backup_database"
    get   "site_sync/backups/download_db", to: "site_sync#download_backup_database", as: "download_backup_database"
    post  "site_sync/restore_database",   to: "site_sync#restore_database", as: "restore_database"
    post  "site_sync/apply_backup_credentials", to: "site_sync#apply_backup_credentials", as: "apply_backup_credentials"
    post  "site_sync/dismiss_restore_recovery", to: "site_sync#dismiss_restore_recovery", as: "dismiss_restore_recovery"
    post "site_sync/config/regenerate_token", to: "site_sync#regenerate_token", as: "regenerate_site_sync_token"
    post "site_sync/refresh_exchange", to: "site_sync#refresh_exchange", as: "refresh_site_sync_exchange"
    post "site_sync/push_to_live",     to: "site_sync#push_to_live",    as: "push_site_to_live"
    post "site_sync/pull_from_live",   to: "site_sync#pull_from_live",  as: "pull_site_from_live"
    post "site_sync/sync",             to: "site_sync#sync",            as: "sync_site"
    post "site_sync/clone_to_live",    to: "site_sync#clone_to_live",   as: "clone_site_to_live"
    post "site_sync/resolve_conflicts", to: "site_sync#resolve_conflicts", as: "resolve_site_sync_conflicts"
    get  "site_sync/transfer_status",         to: "site_sync#transfer_status",        as: "site_transfer_status"
    post "site_sync/transfer_status/dismiss", to: "site_sync#dismiss_transfer_status", as: "dismiss_site_transfer_status"
    post "site_sync/transfer_status/retry",   to: "site_sync#retry_transfer",         as: "retry_site_transfer"

    # Static Site Sync — SFTP push of /static_site to a webhost. Lives
    # under the same /admin/site_sync UI page; separate controller so
    # the actions stay scoped to their own concerns.
    patch "site_sync/static/config",           to: "static_site_sync#update_config",        as: "update_static_site_sync_config"
    post  "site_sync/static/test_connection",  to: "static_site_sync#test_connection",      as: "test_static_site_sync_connection"
    post  "site_sync/static/push",             to: "static_site_sync#push",                 as: "push_static_site"
    post  "site_sync/static/skip_tls_verification", to: "static_site_sync#skip_tls_verification", as: "skip_tls_verification_static_site"
    get   "site_sync/static/download_zip",     to: "static_site_sync#download_zip",         as: "download_static_site_zip"
    get   "site_sync/static/transfer_status",  to: "static_site_sync#transfer_status",      as: "static_site_transfer_status"
    post  "site_sync/static/transfer_status/dismiss", to: "static_site_sync#dismiss_transfer_status", as: "dismiss_static_site_transfer_status"

    # Account settings — change email/password, regenerate recovery codes.
    get   "account",                to: "account#show",                       as: "account"
    patch "account/email",          to: "account#update_email",               as: "update_account_email"
    patch "account/password",       to: "account#update_password",            as: "update_account_password"
    post  "account/recovery_codes", to: "account#regenerate_recovery_codes",  as: "regenerate_account_recovery_codes"

    get "layout/header/edit", to: "layouts#edit_header"
    patch "layout/header", to: "layouts#update_header"
    # Legacy aliases so old links/bookmarks keep working.
    get "layout/navigation/edit", to: "layouts#edit_header"
    patch "layout/navigation", to: "layouts#update_header"
    get "layout/footer/edit", to: "layouts#edit_footer"
    patch "layout/footer", to: "layouts#update_footer"
    get "layout/sidebar/edit", to: "layouts#edit_sidebar"
    patch "layout/sidebar", to: "layouts#update_sidebar"
    delete "layout/sidebar", to: "layouts#destroy_sidebar", as: "destroy_layout_sidebar"
    get "layouts", to: "layouts#index"
    post "layouts/generate_missing", to: "layouts#generate_missing", as: "generate_missing_admin_layouts"

    resources :posts, only: [ :index, :edit, :update, :new, :create, :destroy ] do
      collection do
        get :drafts
        get :unlisted
        get :check_unique
        post :bulk_destroy
        post :bulk_publish
      end
      member do
        post :publish_modal
        patch :unpublish
        post :preview
        get :preview
        patch :rename
        patch :set_duration
        post :duplicate
        post :send_test_email
        get :newsletter_status
      end
    end


    resources :pages, only: [ :index, :edit, :update, :new, :create, :destroy ] do
      collection do
        post :bulk_destroy
        post :bulk_publish
      end
      member do
        post :publish_modal
        patch :unpublish
        post :preview
        get :preview
        patch :rename
        post :duplicate
      end
    end

    resources :medium, only: [ :index, :create, :destroy ] do
      collection do
        get :browse
        get :picker
        get :duration
        get :exists
        post :clear_failed_jobs
        post :queue_missing_variants
        post :prune_variants
        post :bulk_destroy
      end
      member do
        patch :rename
        post :regenerate_variants
        get :card
      end
    end

    resources :documentation, only: [ :index, :new, :create, :edit, :update, :destroy ]

    resources :products do
      collection do
        get :check_sku
        get :suggest_sku
        get :search
        get :next_sku_number
        get :duplicate_skus
        post :bulk_destroy
        post :bulk_publish
      end
      member do
        post :publish_modal
        patch :unpublish
        post :preview
        get :preview
        get :sku_generator
        patch :rename
        post :duplicate
      end
    end

    resources :configs, only: [ :index ] do
      collection do
        get  :new_podcast_setup
        post :preview_podcast_from_rss
        post :create_podcast
        post :add_podcast
        delete :delete_podcast
        delete :delete_podcast_entry
        get :new_members_setup
        post :create_members
        delete :delete_members
        get :new_store_setup
        post :create_store
        delete :delete_store
        get :new_feeds_setup
        get :new_music_setup
      end
    end

    # Integration config pages (Settings → Integrations)
    get    "configs/payments/edit",       to: "configs#edit_payments",          as: "edit_payments_config"
    patch  "configs/payments",            to: "configs#update_payments",        as: "payments_config"
    patch  "configs/payments/live",       to: "configs#update_payments_live",   as: "live_payments_config"
    patch  "configs/payments/mode",       to: "configs#update_payments_mode",   as: "mode_payments_config"
    post   "configs/payments/verify",     to: "configs#verify_payments",        as: "verify_payments_config"
    delete "configs/payments/disconnect", to: "configs#disconnect_payments",    as: "disconnect_payments_config"

    get    "configs/newsletters/edit",                      to: "configs#edit_newsletters",                  as: "edit_newsletters_config"
    patch  "configs/newsletters",                           to: "configs#update_newsletters",                as: "newsletters_config"
    patch  "configs/newsletters/live",                      to: "configs#update_newsletters_live",           as: "live_newsletters_config"
    patch  "configs/newsletters/mode",                      to: "configs#update_newsletters_mode",           as: "mode_newsletters_config"
    post   "configs/newsletters/verify",                    to: "configs#verify_newsletters",                as: "verify_newsletters_config"
    delete "configs/newsletters/disconnect",                to: "configs#disconnect_newsletters",            as: "disconnect_newsletters_config"
    post   "configs/newsletters/regenerate_webhook_token",  to: "configs#regenerate_postmark_webhook_token", as: "regenerate_webhook_token_newsletters_config"

    get    "configs/snipcart/edit",       to: "configs#edit_snipcart",          as: "edit_snipcart_integration_config"
    patch  "configs/snipcart",            to: "configs#update_snipcart",        as: "snipcart_integration_config"
    patch  "configs/snipcart/live",       to: "configs#update_snipcart_live",   as: "live_snipcart_integration_config"
    patch  "configs/snipcart/mode",       to: "configs#update_snipcart_mode",   as: "mode_snipcart_integration_config"
    post   "configs/snipcart/verify",     to: "configs#verify_snipcart",        as: "verify_snipcart_integration_config"
    delete "configs/snipcart/disconnect", to: "configs#disconnect_snipcart",    as: "disconnect_snipcart_integration_config"

    resources :themes, only: [ :index, :destroy ] do
      member do
        get :edit
        patch :update
        post :activate
        post :reset
      end
    end

    resources :system_assets, only: [ :index, :create ] do
      collection do
        get :browse_fonts
        get :browse_images
        get :available_fonts
      end
    end

    resources :members do
      member do
        patch :upgrade_to_paid
        patch :downgrade_to_free
        patch :cancel_membership
        patch :reactivate_membership
      end
    end

    resources :imports, only: [ :index, :new, :create, :show, :destroy ] do
      member do
        get :phase_2
        post :phase_2_run
        get :phase_3
        post :phase_3_run
        get :phase_4
        post :phase_4_run
        post :rollback
        post :rollback_members
        post :rollback_deliveries
        get :resolve_missing_media
        post :attempt_download
        post :resolve_manually
        post :skip_missing_media
        post :reconnect_media
        post :retry_live_fetch
        post :publish_to_live
        post :dismiss_publish_status
        post :refresh_peer_exchange
        get :members
      end
    end

    resources :feed_imports, only: [ :index, :create, :show, :destroy ] do
      collection do
        post :preview
        post :add_show
      end
    end

    resources :file_imports, only: [ :index, :create, :show, :destroy ] do
      collection do
        post :run
      end
    end

    resources :media_imports, only: [ :index, :create ] do
      collection do
        get :status
        delete :dismiss_status
      end
    end

    resources :emails, only: [ :index, :edit, :update ] do
      member do
        post :preview
        get :preview
      end
    end

    get "static_site", to: "static_site#index", as: :static_site
    post "static_site/generate", to: "static_site#generate", as: :generate_static_site
    post "static_site/clean", to: "static_site#clean", as: :clean_static_site
    post "static_site/rebuild", to: "static_site#rebuild", as: :rebuild_static_site
    get "static_site/status", to: "static_site#status", as: :status_static_site

    delete "system_assets/:id", to: "system_assets#destroy", as: "system_asset", constraints: { id: /[^\/]+/ }

    # Separate config edit routes
    get "configs/site/edit", to: "configs#edit_site", as: "edit_site_config"
    get "configs/security/edit", to: "configs#edit_security", as: "edit_security_config"
    patch "configs/security", to: "configs#update_security", as: "update_security_config"
    patch "configs/site", to: "configs#update_site", as: "site_config"

    get "configs/content/edit", to: "configs#edit_content", as: "edit_content_config"
    patch "configs/content", to: "configs#update_content", as: "content_config"

    get   "configs/custom_code/edit", to: "configs#edit_custom_code", as: "edit_custom_code_config"
    patch "configs/custom_code",      to: "configs#update_custom_code", as: "custom_code_config"

    get "configs/fonts/edit", to: "configs#edit_fonts", as: "edit_fonts_config"
    patch "configs/fonts", to: "configs#update_fonts", as: "fonts_config"

    get "configs/podcast/edit", to: "configs#edit_podcast", as: "edit_podcast_config"
    patch "configs/podcast", to: "configs#update_podcast", as: "podcast_config"
    post "configs/podcast/seed_from_rss", to: "configs#seed_podcast_from_rss", as: "seed_podcast_config_from_rss"

    get "configs/cards/edit", to: "configs#edit_cards", as: "edit_cards_config"
    patch "configs/cards", to: "configs#update_cards", as: "cards_config"

    get "configs/collections/edit", to: "configs#edit_collections", as: "edit_collections_config"
    patch "configs/collections", to: "configs#update_collections", as: "collections_config"

    get "configs/feeds/edit", to: "configs#edit_feeds", as: "edit_feeds_config"
    patch "configs/feeds", to: "configs#update_feeds", as: "feeds_config"

    get "configs/music/edit", to: "configs#edit_music", as: "edit_music_config"
    patch "configs/music", to: "configs#update_music", as: "music_config"

    # Drop settings a Roe update stopped reading, from the file they're in.
    post "configs/cleanup", to: "configs#cleanup", as: "cleanup_config"

    # Raw YAML fallback editor for a config whose structured form won't parse.
    get "configs/raw/edit", to: "configs#edit_raw", as: "edit_raw_config"
    patch "configs/raw", to: "configs#update_raw", as: "raw_config"

    get "configs/members/edit", to: "configs#edit_members", as: "edit_members_config"
    patch "configs/members", to: "configs#update_members", as: "members_config"

    get "configs/store/edit", to: "configs#edit_store", as: "edit_store_config"
    patch "configs/store", to: "configs#update_store", as: "store_config"

    get "configs/deploy/edit",           to: "configs#edit_deploy",            as: "edit_deploy_config"
    patch "configs/deploy",                to: "configs#update_deploy",           as: "deploy_config"
    post  "configs/deploy/clear_password", to: "configs#clear_deploy_password",   as: "clear_deploy_password"

    get "configs/development/edit", to: "configs#edit_development", as: "edit_development_config"
    patch "configs/development", to: "configs#update_development", as: "development_config"
    post "configs/development/enable", to: "configs#enable_development", as: "enable_development_admin_configs"
    delete "configs/development", to: "configs#delete_development", as: "delete_development_admin_configs"

    # Content template editors (post / page / product)
    get "settings/templates/:type", to: "settings#edit_template", as: "settings_template", constraints: { type: /post|page|product/ }
    patch "settings/templates/:type", to: "settings#update_template", constraints: { type: /post|page|product/ }
    get "posts/search", to: "posts#search"
    get "posts/card_fields", to: "posts#card_fields"
  end

  # Health check
  get "/health", to: "health#check"

  # Served rather than a file in public/, so the AI-crawler setting takes effect
  # the moment it's saved instead of on the next static build.
  get "/robots.txt", to: "robots#show", defaults: { format: "text" }

  # Member authentication (public-facing)
  post "signin", to: "members/sessions#create"
  delete "signout", to: "members/sessions#destroy"
  get "signin/:token", to: "members/sessions#signin_with_token", as: :token_signin

  # GET aliases for the public signin/signup PAGES. The post routes above
  # handle form submissions to /signin and /signup, but Rails' signin_path
  # / signup_path helpers resolve to those URLs, and a guest redirected
  # there via GET would get a 404. The actual marketing pages live at
  # /sign-in and /sign-up (per their url_name in pages/members/). These
  # aliases keep all existing signin_path / signup_path callers working.
  get "signin", to: redirect("/sign-in")
  get "signup", to: redirect("/sign-up")

  post "signup", to: "members/registrations#create"
  post "signup_and_checkout", to: "members/registrations#create_and_checkout"

  # Member account management
  get "account", to: "members/accounts#show"
  get "account/edit", to: "members/accounts#edit"
  patch "account", to: "members/accounts#update"
  get "account/confirm-email", to: "members/accounts#confirm_email", as: :confirm_email
  # New private feed URLs, when the old ones have been shared or leaked.
  post "account/feeds/regenerate", to: "members/accounts#regenerate_media_token",
       as: :regenerate_media_token
  delete "account", to: "members/accounts#destroy", as: :delete_account
  get "/unsubscribe/:token", to: "members/subscriptions#unsubscribe", as: :unsubscribe
  post "/unsubscribe/:token", to: "members/subscriptions#confirm_unsubscribe"
  post "webhooks/postmark/:token", to: "webhooks/postmark#create", as: :admin_postmark_webhook

  # Public checkout
  post "checkout", to: "checkout#create", as: :create_checkout
  get "checkout/payment-processing", to: "checkout#payment_processing", as: :checkout_payment_processing
  get "checkout/success", to: "checkout#success", as: :checkout_success
  get "checkout/cancel", to: "checkout#cancel", as: :checkout_cancel

  # Public donations (one-time, anonymous-friendly support payments)
  post "donate", to: "donations#create", as: :create_donation
  get "donate/payment-processing", to: "donations#payment_processing", as: :donation_payment_processing
  get "donate/success", to: "donations#success", as: :donation_success
  get "donate/cancel", to: "donations#cancel", as: :donation_cancel

  # Public site
  # Root renders home.md as a regular page through PagesController#show.
  # Same code path as any other public page — no special-case template.
  root to: "pages#show", defaults: { url_name: "home" }

  # Redirect post ID to slug (preserves anchor in browser)
  get "p/:id", to: "posts#show_by_id", constraints: { id: /\d+/ }, as: :post_by_id

  get "posts/:url_name", to: "posts#show", as: :post
  # System-guaranteed docs index.
  get "roe/documentation", to: "documentation#index", as: :roe_documentation
  # Landing page for the bundled Roe docs at the scope root. Baked into the
  # app so every install has it, even without a /documentation-all page.
  # Must precede the dynamic routes below (else :url_name captures "roe").
  get "documentation/roe", to: "documentation#roe_index", as: :roe_docs_index
  # Subdirectory-namespaced docs (e.g. /documentation/roe/<name>). Listed
  # before the flat route so /documentation/<name> only matches root docs.
  get "documentation/:scope/:url_name", to: "documentation#show", as: :scoped_documentation
  get "documentation/:url_name", to: "documentation#show", as: :documentation
  get "store/:url_name", to: "products#show", as: :product
  # get "store/:url_name/validate", to: "products#validate", as: :product_validate, defaults: { format: :json }

  # Collections and posts archive
  get "posts", to: "collections#show", defaults: { filters: "all" }
  get "collections", to: "collections#show", defaults: { filters: "all" }
  get "collections/*filters", to: "collections#show", as: :collection

  # Public search index (client-side site search). Static builds bake the
  # same JSON to /search-index.json so search works with no backend.
  get "search-index.json", to: "search#index", as: :search_index, defaults: { format: "json" }

  # Feeds
  get "feed", to: "feeds#rss", defaults: { format: "xml" }, as: :feed
  get "feed.xml", to: "feeds#rss", defaults: { format: "xml" }
  get "feed.atom", to: "feeds#atom", defaults: { format: "xml" }, as: :feed_atom
  # Named feeds from feeds.yml — a collection query served as RSS/Atom.
  # Members' copies, carrying full paid articles. Declared before the :name
  # routes so /feed/private.xml isn't read as a feed named "private".
  get "feed/private.xml",  to: "feeds#private_rss", defaults: { format: "xml" }, as: :private_feed
  get "feed/private.atom", to: "feeds#private_rss", defaults: { format: "xml", atom: true }, as: :private_feed_atom
  get "feed/:name/private.xml",  to: "feeds#private_named", defaults: { format: "xml" }, as: :private_named_feed
  get "feed/:name/private.atom", to: "feeds#private_named", defaults: { format: "xml", atom: true }, as: :private_named_feed_atom

  get "feed/:name.xml", to: "feeds#named", defaults: { format: "xml" }, as: :named_feed
  get "feed/:name.atom", to: "feeds#named", defaults: { format: "xml", atom: true }, as: :named_feed_atom
  get "/podcast/:podcast_key.xml", to: "feeds#podcast", as: :podcast_feed
  # A music release published as a podcast-format feed. Separate from the
  # Podcast feature — a release never appears in podcast.yml.
  get "/music/:release_key.xml", to: "feeds#music_release", as: :music_release_feed
  # The paid member's copy: full audio for paid tracks, and the only feed a
  # wholly-paid release has. Mirrors the private podcast feed.
  get "/music/:release_key/private.xml", to: "feeds#private_music_release", as: :private_music_release_feed
  get "/podcast/:podcast_key/private.xml", to: "feeds#private_podcast", as: :private_podcast_feed

  # Theme CSS
  get "theme/:filename.css", to: "system/themes#show", defaults: { format: "css" }
  get "theme/:filename.js", to: "system/themes#show", defaults: { format: "js" }
  # Theme assets (CSS and JS)
  # get 'theme/:filename', to: 'system/themes#show'

  # Roe bundled site JavaScript (search.js, etc.) — served from /javascript
  # so the same layout path works in dynamic and static builds.
  get "javascript/:filename.js", to: "system/javascripts#show", defaults: { format: "js" }, constraints: { filename: /[^\/]+/ }

  # System assets
  get "system/fonts/:filename", to: "system/fonts#show", as: :system_font, constraints: { filename: /[^\/]+/ }
  get "system/images/:filename", to: "system/images#show", as: :system_image, constraints: { filename: /[^\/]+/ }

  # Media files
  get "/media/*path", to: "media#show", format: false

  # Stripe webhooks
  post "webhooks/stripe", to: "webhooks#stripe", as: :stripe_webhook

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page
end

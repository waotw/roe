Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication (specific routes first)
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token

  # Admin area (specific routes before catch-all)
  namespace :admin do
    root "dashboard#index"

    get "layout/navigation/edit", to: "layouts#edit_navigation"
    patch "layout/navigation", to: "layouts#update_navigation"
    get "layout/footer/edit", to: "layouts#edit_footer"
    patch "layout/footer", to: "layouts#update_footer"
    get "layouts", to: "layouts#index"

    resources :posts, only: [ :index, :edit, :update, :new, :create, :destroy ] do
      collection do
        get :drafts
        get :unlisted
      end
      member do
        patch :publish
        get :publish_modal
        post :confirm_publish
        patch :unpublish
        post :preview
        get :preview
        patch :rename
        post :send_test_email
        get :resend_modal
        post :confirm_resend
        post :resend_newsletter
        get :newsletter_status
      end
    end


    resources :pages, only: [ :index, :edit, :update, :new, :create, :destroy ] do
      member do
        patch :publish
        patch :unpublish
        post :preview
        get :preview
        patch :rename
      end
    end

    resources :medium, only: [ :index, :create, :destroy ] do
      collection do
        get :browse
        get :duration
      end
      member do
        patch :rename
      end
    end

    resources :documentation, only: [ :index, :new, :create, :edit, :update, :destroy ]

    resources :configs, only: [:index] do
      collection do
        post :generate_podcast
        delete :delete_podcast
        get :new_members_setup
        post :create_members
        delete :delete_members
      end
    end

    # Stripe Configuration
    resource :stripe_config, only: [:edit, :update, :destroy]

    # Postmark Configuration
    resource :postmark_config, only: [:edit, :update, :destroy] do
      post :regenerate_webhook_token, on: :member
    end

    resources :themes, only: [:index] do
      member do
        get :edit
        patch :update
        post :activate
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

    resources :emails, only: [:index, :edit, :update] do
      member do
        post :preview
        get :preview
      end
    end

    get 'static_site', to: 'static_site#index', as: :static_site
    post 'static_site/generate', to: 'static_site#generate', as: :generate_static_site
    post 'static_site/clean', to: 'static_site#clean', as: :clean_static_site
    post 'static_site/rebuild', to: 'static_site#rebuild', as: :rebuild_static_site
    get 'static_site/status', to: 'static_site#status', as: :status_static_site

    delete 'system_assets/:id', to: 'system_assets#destroy', as: 'system_asset', constraints: { id: /[^\/]+/ }

    # Separate config edit routes
    get 'configs/site/edit', to: 'configs#edit_site', as: 'edit_site_config'
    patch 'configs/site', to: 'configs#update_site', as: 'site_config'

    get 'configs/podcast/edit', to: 'configs#edit_podcast', as: 'edit_podcast_config'
    patch 'configs/podcast', to: 'configs#update_podcast', as: 'podcast_config'

    get 'configs/cards/edit', to: 'configs#edit_cards', as: 'edit_cards_config'
    patch 'configs/cards', to: 'configs#update_cards', as: 'cards_config'

    get 'configs/collections/edit', to: 'configs#edit_collections', as: 'edit_collections_config'
    patch 'configs/collections', to: 'configs#update_collections', as: 'collections_config'

    get 'configs/members/edit', to: 'configs#edit_members', as: 'edit_members_config'
    patch 'configs/members', to: 'configs#update_members', as: 'members_config'

    # Post template editor
    get "settings/post_template", to: "settings#edit_post_template"
    patch "settings/post_template", to: "settings#update_post_template"
    get 'posts/search', to: 'posts#search'
  end

  # Health check
  get '/health', to: 'health#check'

  # Member authentication (public-facing)
  post "signin", to: "members/sessions#create"
  delete "signout", to: "members/sessions#destroy"
  get 'signin/:token', to: 'members/sessions#signin_with_token', as: :token_signin

  post 'signup', to: 'members/registrations#create'
  post 'signup_and_checkout', to: 'members/registrations#create_and_checkout'

  # Member account management
  get "account", to: "members/accounts#show"
  get "account/edit", to: "members/accounts#edit"
  patch "account", to: "members/accounts#update"
  get "account/confirm-email", to: "members/accounts#confirm_email", as: :confirm_email
  get '/unsubscribe/:token', to: 'members/subscriptions#unsubscribe', as: :unsubscribe
  post '/unsubscribe/:token', to: 'members/subscriptions#confirm_unsubscribe'
  post 'webhooks/postmark/:token', to: 'webhooks/postmark#create', as: :admin_postmark_webhook

  # Public checkout
  post 'checkout', to: 'checkout#create', as: :create_checkout
  get 'checkout/success', to: 'checkout#success', as: :checkout_success
  get 'checkout/cancel', to: 'checkout#cancel', as: :checkout_cancel

  # Public site (specific before catch-all)
  root "posts#index"

  # Redirect post ID to slug (preserves anchor in browser)
  get 'p/:id', to: 'posts#show_by_id', constraints: { id: /\d+/ }, as: :post_by_id

  get "posts/:url_name", to: "posts#show", as: :post
  get "documentation/:url_name", to: "documentation#show", as: :documentation

  # Collections and posts archive
  get 'posts', to: 'collections#show', defaults: { filters: 'all' }
  get 'collections/*filters', to: 'collections#show', as: :collection

  # Feeds
  get "feed", to: "feeds#rss", defaults: { format: 'xml' }, as: :feed
  get "feed.xml", to: "feeds#rss", defaults: { format: 'xml' }
  get "feed.atom", to: "feeds#atom", defaults: { format: 'xml' }, as: :feed_atom
  get '/podcast/:podcast_key.xml', to: 'feeds#podcast', as: :podcast_feed

  # Theme CSS (before catch-all)
  get 'theme/:filename.css', to: 'system/themes#show', defaults: { format: 'css' }
  get 'theme/:filename.js', to: 'system/themes#show', defaults: { format: 'js' }
  # Theme assets (CSS and JS)
  # get 'theme/:filename', to: 'system/themes#show'

  # System assets
  get 'system/fonts/:filename', to: 'system/fonts#show', as: :system_font, constraints: { filename: /[^\/]+/ }
  get 'system/images/:filename', to: 'system/images#show', as: :system_image, constraints: { filename: /[^\/]+/ }

  # Media files
  get '/media/*path', to: 'media#show', format: false

  # Stripe webhooks
  post 'webhooks/stripe', to: 'webhooks#stripe', as: :stripe_webhook

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page
end

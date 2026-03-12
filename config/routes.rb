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

    resources :posts, only: [ :index, :edit, :update, :new, :create ] do
      collection do
        get :drafts
        get :unlisted
      end
      member do
        patch :publish
        patch :unpublish
        post :preview
      end
    end

    resources :pages, only: [ :index, :edit, :update, :new, :create ] do
      member do
        patch :publish
        patch :unpublish
        post :preview
      end
    end

    resources :medium, only: [ :index, :create, :destroy ] do
      collection do
        get :browse
      end
    end

    resources :documentation, only: [ :index, :new, :create, :edit, :update, :destroy ]

    resources :configs, only: [ :index ]

    resources :system_assets, only: [ :index, :create ] do
      collection do
        get :browse_fonts
        get :browse_images
      end
    end

    delete 'system_assets/:id', to: 'system_assets#destroy', as: 'system_asset', constraints: { id: /[^\/]+/ }

    # Separate config edit routes
    get 'configs/site/edit', to: 'configs#edit_site', as: 'edit_site_config'
    patch 'configs/site', to: 'configs#update_site', as: 'site_config'

    get 'configs/cards/edit', to: 'configs#edit_cards', as: 'edit_cards_config'
    patch 'configs/cards', to: 'configs#update_cards', as: 'cards_config'

    get 'configs/collections/edit', to: 'configs#edit_collections', as: 'edit_collections_config'
    patch 'configs/collections', to: 'configs#update_collections', as: 'collections_config'

    # Post template editor
    get "settings/post_template", to: "settings#edit_post_template"
    patch "settings/post_template", to: "settings#update_post_template"
    get 'posts/search', to: 'posts#search'
  end

  # Public site (specific before catch-all)
  root "posts#index"
  get "posts/:url_name", to: "posts#show", as: :post
  get "documentation/:url_name", to: "documentation#show", as: :documentation

  # Feeds
  get "feed", to: "feeds#rss", defaults: { format: 'xml' }, as: :feed
  get "feed.xml", to: "feeds#rss", defaults: { format: 'xml' }
  get "feed.atom", to: "feeds#atom", defaults: { format: 'xml' }, as: :feed_atom

  # System assets
  get 'system/fonts/:filename', to: 'system/fonts#show', as: :system_font, constraints: { filename: /[^\/]+/ }
  get 'system/images/:filename', to: 'system/images#show', as: :system_image, constraints: { filename: /[^\/]+/ }

  # Media files
  get '/media/*path', to: 'media#show', format: false

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page
end

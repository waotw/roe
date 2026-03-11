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

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page

  get '/media/*path', to: 'media#show', format: false
end

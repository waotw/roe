Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication (specific routes first)
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token

  # Admin area (specific routes before catch-all)
  namespace :admin do
    root "dashboard#index"

    get "layout/header/edit", to: "layouts#edit_header"  # Correct - plural
    patch "layout/header", to: "layouts#update_header"
    get "layout/footer/edit", to: "layouts#edit_footer"
    patch "layout/footer", to: "layouts#update_footer"
    get "layouts", to: "layouts#index"

    resources :posts, only: [ :index, :edit, :update, :new, :create ] do
      collection do
        get :drafts       # This creates admin_posts_drafts_path
        get :unlisted     # This creates admin_posts_unlisted_path
      end
      member do
        patch :publish
        patch :unpublish
      end
    end

    resources :pages, only: [ :index, :edit, :update, :new, :create ] do
        member do
          patch :publish      # Add these
          patch :unpublish    # Add these
        end
      end

    # Post template editor
    get "settings/post_template", to: "settings#edit_post_template"
    patch "settings/post_template", to: "settings#update_post_template"
  end

  # Public site (specific before catch-all)
  root "posts#index"
  get "posts/:url_name", to: "posts#show", as: :post

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page
end

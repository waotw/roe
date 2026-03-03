Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication (specific routes first)
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token

  # Admin area (specific routes before catch-all)
  namespace :admin do
    root "dashboard#index"
    resources :posts, only: [ :index ]
    resources :pages, only: [ :index ]
    get "drafts", to: "posts#drafts"
  end

  # Public site (specific before catch-all)
  root "posts#index"
  get "posts/:url_name", to: "posts#show", as: :post

  # Pages catch-all (MUST BE LAST)
  get ":url_name", to: "pages#show", as: :page
end

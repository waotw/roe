Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  resource :session, only: [:new, :create, :destroy]
  resources :passwords, param: :token

  # Public site
  root "posts#index"
  get "posts/:url_name", to: "posts#show", as: :post
  get ":url_name", to: "pages#show", as: :page
end

Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Posts routes
  root "posts#index"
  get "posts/:url_name", to: "posts#show", as: :post
end

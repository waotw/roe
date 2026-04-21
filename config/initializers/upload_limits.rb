# config/initializers/upload_limits.rb
BULK_UPLOAD_LIMITS = {
  development: 50,
  production: 0,  # No bulk upload in production
  test: 10
}.freeze

MAX_BULK_UPLOAD = Rails.env.production? ? 20 : 50

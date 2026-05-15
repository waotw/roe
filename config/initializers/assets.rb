# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
Rails.application.config.assets.paths << Rails.root.join("vendor", "stylesheets")
Rails.application.config.assets.paths << Rails.root.join("vendor", "javascript")

# tailwindcss-rails outputs to app/assets/builds/. The gem registers this
# path in some environments but not reliably during production
# precompile — without it, tailwind.css ends up missing from the
# precompiled manifest and the layout's stylesheet_link_tag "tailwind"
# raises Propshaft::MissingAssetError on first request. Adding it
# explicitly is idempotent (Propshaft dedupes paths) and safe.
Rails.application.config.assets.paths << Rails.root.join("app", "assets", "builds")

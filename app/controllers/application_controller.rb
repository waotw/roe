class ApplicationController < ActionController::Base
  include Authentication
  include MemberAuthentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  layout "site"

  # Render 404 for RecordNotFound
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def setup_theme_preview
    if authenticated? && params[:preview_theme].present?
      @preview_mode = true
      @preview_id = "theme-#{params[:preview_theme]}"
    end
  end

  def render_not_found
    static_404 = Rails.root.join("public", "404.html")
    if File.exist?(static_404)
      render file: static_404.to_s, status: :not_found, layout: false
    else
      render html: "<h1 style='font-family:sans-serif;padding:2rem'>404 &mdash; Page not found</h1>".html_safe,
             status: :not_found, layout: false
    end
  end
end

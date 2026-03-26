class ApplicationController < ActionController::Base
  include Authentication
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
    render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
  end
end

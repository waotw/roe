class ApplicationController < ActionController::Base
  include Authentication
  include MemberAuthentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  layout "site"

  # Render 404 for RecordNotFound
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Redirect after a non-GET request with 303 See Other, not Rails' default 302.
  #
  # A 302 preserves the request method for everything except POST. So a PATCH
  # that gets refused and redirected is re-issued as a PATCH to wherever it was
  # sent — and if that route is also non-GET, it redirects again. A guard on
  # Admin::MembersController did exactly this: refusing a PATCH to a deleted
  # member redirected to the member page, which routes to #update, which the
  # same guard refused. The client got ERR_TOO_MANY_REDIRECTS instead of the
  # reason it was refused.
  #
  # It stayed hidden because Rails forms send POST with a _method field, and
  # 302 does downgrade POST to GET. Only a real PATCH or DELETE — fetch, curl,
  # an API client — loops.
  #
  # 303 says "the answer is elsewhere, go and GET it", which is what every one
  # of these redirects means. Turbo requires it after a non-GET too.
  #
  # Here rather than at 144 call sites across 29 controllers: one rule, no
  # chance of missing one, and it covers code not written yet. An explicit
  # status: on any individual redirect still wins.
  def redirect_to(options = {}, response_options = {})
    if !request.get? && !request.head? && !response_options.key?(:status)
      response_options[:status] = :see_other
    end

    super
  end

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

class PagesController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  before_action :setup_theme_preview

  def show
    @page = Page.all.find { |p| p.url_name == params[:url_name] }

    raise ActiveRecord::RecordNotFound unless @page

    # Allow authenticated users to see drafts, otherwise only published
    unless @page.published? || authenticated?
      raise ActiveRecord::RecordNotFound
    end
  end

  private
end

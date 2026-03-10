class DocumentationController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  def show
    @doc = Documentation.all.find { |d| d.url_name == params[:url_name] }

    raise ActiveRecord::RecordNotFound unless @doc

    # For now, docs are always viewable
    # Later you could add: unless @doc.published? || authenticated?
  end
end

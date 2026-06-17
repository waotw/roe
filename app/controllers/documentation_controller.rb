class DocumentationController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  # System docs landing page. Always available at /roe/documentation
  # regardless of what user-authored pages exist. The user's own
  # /documentation page (if they have one) is a separate, user-
  # controlled view and is unaffected by this action.
  #
  # Renders through the same markdown → collection-block pipeline a
  # user-authored page would, by building a synthetic Page with a
  # ```collection``` fence in its content. That way the resulting
  # HTML, CSS class names (`collection list`, `collection-item`,
  # `.item-title`, etc.), and item ordering match exactly what the
  # active theme already styles — no separate styling surface to
  # keep in sync with the theme.
  def index
    @docs_html = Page.new(content: index_markdown).to_html
  end

  def show
    @doc = Documentation.all.find { |d| d.url_name == params[:url_name] }

    raise ActiveRecord::RecordNotFound unless @doc

    # Back-link target. Prefer the user's /documentation page when
    # it exists (consistent with how they likely arrived); fall
    # back to the system route so the link is never dead.
    @back_path = user_documentation_page_path || roe_documentation_path

    # For now, docs are always viewable
    # Later you could add: unless @doc.published? || authenticated?
  end

  private

  def index_markdown
    <<~MD
      # Documentation

      ```collection
      source: documentation
      template: list
      order: filename
      limit: all
      ```
    MD
  end

  # Returns `/documentation` if the user has published a page at
  # that slug, otherwise nil. Iterates Page.public_pages because
  # url_name can be either explicit in metadata OR derived from
  # title at read time, and only the iteration sees both.
  def user_documentation_page_path
    has_user_page = Page.public_pages.any? { |p| p.url_name == "documentation" }
    has_user_page ? page_path("documentation") : nil
  end
end

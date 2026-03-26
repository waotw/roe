class PostsController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  before_action :setup_theme_preview

  def index
    @home_page = Page.all.find { |p| p.file_path.end_with?('home.md') }
  end

  def show
    @post = Post.all.find { |p| p.url_name == params[:url_name] }

    raise ActiveRecord::RecordNotFound unless @post

    # Allow authenticated users to see drafts, otherwise only public posts
    unless @post.published? || @post.unlisted? || authenticated?
      raise ActiveRecord::RecordNotFound
    end
  end

  private
end

class PostsController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  def index
    @home_page = Page.all.find { |p| p.file_path.end_with?('home.md') }
  end

  def show
    puts "Looking for url_name: #{params[:url_name]}"

    # Debug: show all post url_names
    Post.all.each do |p|
      puts "Post file: #{p.file_path}, url_name: #{p.url_name}"
    end

    @post = Post.all.find { |p| p.url_name == params[:url_name] }

    puts "Found post: #{@post.inspect}"

    raise ActiveRecord::RecordNotFound unless @post

    # Allow authenticated users to see drafts, otherwise only public posts
    unless @post.published? || @post.unlisted? || authenticated?
      raise ActiveRecord::RecordNotFound
    end
  end

  private
end

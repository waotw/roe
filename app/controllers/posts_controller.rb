class PostsController < ApplicationController
  layout "site"

  def index
    # Only show published posts in feed (not unlisted)
    @posts = Post.feed_posts
                 .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
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

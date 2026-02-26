class PostsController < ApplicationController
  def index
    @posts = Post.order(date: :desc)
  end

  def show
    # Now find by the filename instead of url_name column
    filename = "#{params[:url_name]}.md"
    @post = Post.find_by!("file_path LIKE ?", "%#{filename}")
  end
end

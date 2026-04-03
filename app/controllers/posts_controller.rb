class PostsController < SiteController
  def index
    @home_page = Page.all.find { |p| p.file_path.end_with?('home.md') }
  end

  def show
    @post = Post.all.find { |p| p.url_name == params[:url_name] }
    raise ActiveRecord::RecordNotFound unless @post

    check_draft_access!(@post)
    check_paid_access!(@post)
  end

  def show_by_id
    @post = Post.find(params[:id])
    redirect_to post_path(@post.url_name), status: :moved_permanently
  end
end

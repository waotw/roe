class PostsController < SiteController
  def index
    @home_page = Page.all.find { |p| p.file_path.end_with?('home.md') }
  end

  def show
    @post = Post.all.find { |p| p.url_name == params[:url_name] }
    raise ActiveRecord::RecordNotFound unless @post

    check_draft_access!(@post)
    check_paid_access!(@post)

    # Load podcast config and sibling episodes for podcast posts
    if @post.post_type == "podcast" && @post.metadata["podcast"].present?
      @podcast_config = PodcastConfig.get(@post.metadata["podcast"])
      @podcast_episodes = Post
        .published
        .where("json_extract(metadata, '$.post_type') = ?", "podcast")
        .where("json_extract(metadata, '$.podcast') = ?", @post.metadata["podcast"])
        .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
        .to_a
    end
  end

  def show_by_id
    @post = Post.find(params[:id])
    redirect_to post_path(@post.url_name), status: :moved_permanently
  end
end

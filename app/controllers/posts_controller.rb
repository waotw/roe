class PostsController < ApplicationController
  layout "site"

  def index
    # Order by date in JSON metadata
    @posts = Post.published
                 .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
  end

  def show
    filename = "#{params[:url_name]}.md"
    @post = Post.find_by!("file_path LIKE ?", "%#{filename}")

    # Don't show drafts on public site
    if @post.draft?
      raise ActiveRecord::RecordNotFound
    end
  end
end

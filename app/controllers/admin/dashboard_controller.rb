class Admin::DashboardController < Admin::BaseController
  def index
    @posts_count = Post.count
    @published_posts_count = Post.published.count
    @draft_posts_count = Post.drafts.count
    @pages_count = Page.count
  end
end

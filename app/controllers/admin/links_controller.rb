class Admin::LinksController < Admin::BaseController
  # GET /admin/links — the last links check, in full.
  def index
    @result = LinkCheck.latest
  end

  # POST /admin/links/check — CHECK NOW. Runs here rather than in the
  # background, so the page it returns to shows the new result. Back to
  # wherever it was pressed (the dashboard or the Links page).
  def check
    LinkCheck.run!(reason: "check")
    redirect_back fallback_location: admin_links_path
  end
end

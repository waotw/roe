class PagesController < SiteController
  def show
    @page = Page.all.find { |p| p.url_name == params[:url_name] }
    raise ActiveRecord::RecordNotFound unless @page

    check_draft_access!(@page)
    check_paid_access!(@page)
  end

  # `/` is always the home page (Page.home), whatever it's called.
  def home
    @page = Page.home
    raise ActiveRecord::RecordNotFound unless @page

    check_draft_access!(@page)
    check_paid_access!(@page)
    render :show
  end
end

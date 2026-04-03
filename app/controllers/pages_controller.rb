class PagesController < SiteController
  def show
    @page = Page.all.find { |p| p.url_name == params[:url_name] }
    raise ActiveRecord::RecordNotFound unless @page

    check_draft_access!(@page)
    check_paid_access!(@page)
  end
end

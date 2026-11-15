# Admin-only pages showing every element a theme styles, in the site's own
# layout. ?preview_theme=<name> shows any installed theme without making it
# active; the site layout already reads that parameter for the theme editor's
# preview, and marks the page noindex while it's set. See ThemeReference.
class Admin::ThemeReferenceController < Admin::BaseController
  layout "site"

  # Signed in, an admin sees paid content whole, with the paywall taken out.
  # The Forms & Members page shows the paywall as a visitor sees it.
  helper do
    def should_truncate_content?(item)
      item.audience == "paid"
    end
  end

  def show
    @reference_page = ThemeReference.find(params[:page].presence || ThemeReference::PAGES.first.slug)
    raise ActiveRecord::RecordNotFound unless @reference_page

    @reference_themes = installed_themes
    if params[:preview_theme].present? && !@reference_themes.include?(params[:preview_theme])
      return redirect_to admin_theme_reference_path(@reference_page.slug)
    end
    @reference_theme = params[:preview_theme].presence || SiteConfig.get("theme.active") || "default"

    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    show_flash_examples if @reference_page.slug == "layout"
    ThemeReference.with_sample_content do
      @page = ThemeReference.record(@reference_page)
      render :show
    end
  end

  private

  # The site layout draws flash messages itself, so the Layout page shows
  # them by setting real ones for this request only.
  # COPY: example flash messages
  def show_flash_examples
    flash.now[:notice] = "A notice, as shown after a form is sent"
    flash.now[:alert] = "An alert, as shown when something went wrong"
  end

  # The themes in site/theme/, the ones /theme/<name>.css can serve.
  def installed_themes
    Dir.glob(File.join(RoeSitePaths::SITE_PATH, "theme", "*.css"))
       .map { |path| File.basename(path, ".css") }
       .sort
  end
end

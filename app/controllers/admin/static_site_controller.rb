module Admin
  class StaticSiteController < AdminController
    def index
      @last_generation = Rails.cache.read('static_site:last_generation')
    end

    def generate
      GenerateStaticSiteJob.perform_later

      flash[:notice] = "Static site generation started. This may take a few moments."
      redirect_to admin_static_site_path
    end

    def status
      stats = Rails.cache.read('static_site:last_stats') || {}
      render json: stats
    end
  end
end

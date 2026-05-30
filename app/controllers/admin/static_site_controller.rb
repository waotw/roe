module Admin
  class StaticSiteController < ApplicationController
    layout "application"

    def index
      @last_generation = Rails.cache.read("static_site:last_generation")
      @last_stats = Rails.cache.read("static_site:last_stats") || {}
      @generation_enabled = SiteConfig.get("static_generation_enabled")
    end

    def generate
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("site:generate")
      Rake::Task["site:generate"].execute

      flash[:notice] = "Static site generation complete."
      redirect_to admin_static_site_path
    end

    def clean
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("site:clean")
      Rake::Task["site:clean"].execute

      flash[:notice] = "Static site files cleaned."
      redirect_to admin_static_site_path
    end

    def rebuild
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("site:rebuild")
      Rake::Task["site:rebuild"].execute

      flash[:notice] = "Static site rebuild complete."
      redirect_to admin_static_site_path
    end

    def status
      stats = Rails.cache.read("static_site:last_stats") || {}
      render json: stats
    end
  end
end

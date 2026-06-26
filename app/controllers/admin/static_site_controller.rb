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
    rescue => e
      # site:generate raises when generation finishes with non-fatal
      # errors (e.g. a single post failed to render). The site itself
      # is still generated and usable — the raise just makes the CLI
      # exit status reflect partial failure. In the web flow we want
      # to surface the error count without 500'ing the request.
      flash[:alert] = "Static site generated with errors: #{e.message}. Check the server log for the per-item details."
      redirect_to admin_static_site_path
    end

    def clean
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("site:clean")
      Rake::Task["site:clean"].execute

      flash[:notice] = "Static site files cleaned."
      redirect_to admin_static_site_path
    rescue => e
      flash[:alert] = "Static site clean failed: #{e.message}"
      redirect_to admin_static_site_path
    end

    def rebuild
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("site:rebuild")
      Rake::Task["site:rebuild"].execute

      flash[:notice] = "Static site rebuild complete."
      redirect_to admin_static_site_path
    rescue => e
      flash[:alert] = "Static site rebuild completed with errors: #{e.message}"
      redirect_to admin_static_site_path
    end

    def status
      stats = Rails.cache.read("static_site:last_stats") || {}
      render json: stats
    end
  end
end

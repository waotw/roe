class Admin::ConfigsController < ApplicationController
  layout 'application'

  def index
    @config_files = [
      {
        section: "📁 Site",
        files: [
          { name: "site.yml", path: admin_edit_site_config_path, description: "Site metadata, branding, and fonts" }
        ]
      },
      {
        section: "📁 Defaults",
        files: [
          { name: "cards.yml", path: admin_edit_cards_config_path, description: "Default card templates" },
          { name: "collections.yml", path: admin_edit_collections_config_path, description: "Default collection settings" }
        ]
      }
    ]
  end

  def edit_site
    @config_type = 'site'
    @config_content = File.read(SiteConfig::SITE_FILE)
    render :edit
  end

  def update_site
    update_config('site', SiteConfig::SITE_FILE)
  end

  def edit_cards
    @config_type = 'cards'
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join('cards.yml'))
    render :edit
  end

  def update_cards
    update_config('defaults/cards', SiteConfig::DEFAULTS_PATH.join('cards.yml'))
  end

  def edit_collections
    @config_type = 'collections'
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join('collections.yml'))
    render :edit
  end

  def update_collections
    update_config('defaults/collections', SiteConfig::DEFAULTS_PATH.join('collections.yml'))
  end

  private

  def update_config(type, file_path)
    content = params[:content]

    # Validate YAML syntax
    begin
      YAML.load(content)
    rescue Psych::SyntaxError => e
      flash.now[:error] = "Invalid YAML syntax: #{e.message}"
      @config_type = type.split('/').last
      @config_content = content
      render :edit and return
    end

    # Write to file
    File.write(file_path, content)

    # Sync to database and clear cache
    SiteConfig.sync_from_file(type)

    flash[:notice] = "#{type.split('/').last.capitalize} configuration updated successfully"
    redirect_to admin_configs_path
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type = type.split('/').last
    @config_content = content
    render :edit
  end
end

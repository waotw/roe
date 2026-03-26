class Admin::ThemesController < ApplicationController
  layout 'application'

  THEMES_DIR = Rails.root.join('app/themes')
  USER_THEME_DIR = Rails.root.join('site/theme')

  def index
    @available_themes = list_available_themes
    @active_theme = get_active_theme
    @active_theme_exists = File.exist?(USER_THEME_DIR.join("#{@active_theme}.css"))

    # Add installation status to each theme
    @available_themes.each do |theme|
      theme[:installed] = File.exist?(USER_THEME_DIR.join("#{theme[:name]}.css"))
    end
  end

  def edit
    @theme_name = params[:id]
    @theme_file = USER_THEME_DIR.join("#{@theme_name}.css")

    unless @theme_file.exist?
      flash[:error] = "Theme '#{@theme_name}' not found in your theme folder"
      redirect_to admin_themes_path and return
    end

    @theme_content = File.read(@theme_file)
    @preview_id = "theme-#{@theme_name}"
  end

  def update
    theme_name = params[:id]
    theme_file = USER_THEME_DIR.join("#{theme_name}.css")

    File.write(theme_file, params[:content])

    flash[:notice] = "#{theme_name.capitalize} theme updated successfully"
    redirect_to edit_admin_theme_path(theme_name)
  rescue => e
    flash[:error] = "Failed to update theme: #{e.message}"
    @theme_name = theme_name
    @theme_content = params[:content]
    render :edit
  end

  def activate
    theme_name = params[:id]  # Changed from params[:name]
    source_file = THEMES_DIR.join("#{theme_name}.css")

    unless source_file.exist?
      flash[:error] = "Theme '#{theme_name}' not found in app/themes/"
      redirect_to admin_themes_path and return
    end

    # Copy theme to user's theme folder
    FileUtils.mkdir_p(USER_THEME_DIR)
    dest_file = USER_THEME_DIR.join("#{theme_name}.css")
    FileUtils.cp(source_file, dest_file)

    # Update site config
    update_active_theme(theme_name)

    flash[:notice] = "#{theme_name.capitalize} theme activated and copied to /site/theme/"
    redirect_to admin_themes_path
  end

  private

  def list_available_themes
    Dir.glob(THEMES_DIR.join('*.css')).map do |file|
      {
        name: File.basename(file, '.css'),
        path: file,
        size: File.size(file)
      }
    end.sort_by { |t| t[:name] }
  end

  def get_active_theme
    site_file = SiteConfig::SITE_FILE
    return 'default' unless File.exist?(site_file)

    config = YAML.safe_load_file(site_file, permitted_classes: [Date, Time, Symbol]) || {}
    config.dig('theme', 'active') || 'default'
  end

  def update_active_theme(theme_name)
    site_file = SiteConfig::SITE_FILE

    # Read existing config
    config = if File.exist?(site_file)
      YAML.safe_load_file(site_file, permitted_classes: [Date, Time, Symbol]) || {}
    else
      {}
    end

    # Update theme
    config['theme'] ||= {}
    config['theme']['active'] = theme_name

    # Write back to file (preserving structure)
    File.write(site_file, config.to_yaml)

    # Sync to database and clear cache
    SiteConfig.sync_from_file('site')
  end
end

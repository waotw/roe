class Admin::ThemesController < Admin::BaseController

  THEMES_DIR = Rails.root.join('app/themes')
  USER_THEME_DIR = Pathname.new(File.join(RoeSitePaths::SITE_PATH, 'theme'))

  def index
    @available_themes = list_available_themes
    @active_theme = get_active_theme
    @active_theme_exists = File.exist?(USER_THEME_DIR.join("#{@active_theme}.css"))

    # Add installation status to each theme (checks if file exists in user's theme folder)
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
    @suggested_copy_name = generate_unique_theme_name(@theme_name)
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

  def reset
    theme_name = params[:id]
    reset_type = params[:reset_type]
    custom_name = params[:custom_name]&.strip

    source_file = THEMES_DIR.join("#{theme_name}.css")

    unless source_file.exist?
      flash[:error] = "Original theme '#{theme_name}' not found in app/themes/"
      redirect_to edit_admin_theme_path(theme_name) and return
    end

    if reset_type == 'overwrite'
      # Reset to original - overwrite existing file
      dest_file = USER_THEME_DIR.join("#{theme_name}.css")
      FileUtils.cp(source_file, dest_file)
      flash[:notice] = "#{theme_name.capitalize} theme reset to original. Your customizations have been overwritten."
      redirect_to edit_admin_theme_path(theme_name)
    elsif reset_type == 'fresh'
      # Install fresh copy with custom/new name
      new_name = custom_name.presence || generate_unique_theme_name(theme_name)
      dest_file = USER_THEME_DIR.join("#{new_name}.css")

      if dest_file.exist?
        flash[:error] = "A theme named '#{new_name}' already exists. Please choose a different name."
        redirect_to edit_admin_theme_path(theme_name) and return
      end

      FileUtils.cp(source_file, dest_file)
      flash[:notice] = "Fresh copy installed as '#{new_name}'. Your original theme remains unchanged."
      redirect_to edit_admin_theme_path(new_name)
    else
      flash[:error] = "Invalid reset type"
      redirect_to edit_admin_theme_path(theme_name)
    end
  end

  def destroy
    theme_name = params[:id]
    theme_file = USER_THEME_DIR.join("#{theme_name}.css")

    # Check if this is the currently active theme
    if theme_name == get_active_theme
      flash[:error] = "Cannot uninstall the currently active theme. Please activate a different theme first."
      redirect_to admin_themes_path and return
    end

    unless theme_file.exist?
      flash[:error] = "Theme '#{theme_name}' not found"
      redirect_to admin_themes_path and return
    end

    FileUtils.rm(theme_file)
    flash[:notice] = "#{theme_name.capitalize} theme uninstalled successfully"
    redirect_to admin_themes_path
  end

  private

  def list_available_themes
    themes = {}

    # First, collect master themes from /app/themes/
    Dir.glob(THEMES_DIR.join('*.css')).each do |file|
      name = File.basename(file, '.css')
      themes[name] = {
        name: name,
        path: file,
        size: File.size(file),
        master: true
      }
    end

    # Then, add user themes from /site/theme/ that aren't already listed
    Dir.glob(USER_THEME_DIR.join('*.css')).each do |file|
      name = File.basename(file, '.css')
      unless themes.key?(name)
        themes[name] = {
          name: name,
          path: file,
          size: File.size(file),
          master: false
        }
      end
    end

    themes.values.sort_by { |t| t[:name] }
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

  def generate_unique_theme_name(base_name)
    counter = 1
    proposed_name = "#{base_name}-copy"

    while File.exist?(USER_THEME_DIR.join("#{proposed_name}.css"))
      proposed_name = "#{base_name}-copy-#{counter}"
      counter += 1
    end

    proposed_name
  end
end

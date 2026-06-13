class Admin::ThemesController < Admin::BaseController
  THEMES_DIR = Rails.root.join("app/themes")
  USER_THEME_DIR = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "theme"))

  def index
    @available_themes = list_available_themes
    @active_theme = get_active_theme
    @active_theme_exists = File.exist?(USER_THEME_DIR.join("#{@active_theme}.css"))

    # Enrich each theme entry with version + update status so the view
    # can show "v1.0.0 (update available)" or "custom" badges per row.
    @available_themes.each do |theme|
      installed_path = USER_THEME_DIR.join("#{theme[:name]}.css")
      bundled_path   = theme[:master] ? theme[:path] : nil

      theme[:installed] = File.exist?(installed_path)

      bundled_header   = bundled_path ? ThemeInspector.parse_header(bundled_path) : nil
      installed_header = theme[:installed] ? ThemeInspector.parse_header(installed_path) : nil

      theme[:display_name]      = installed_header&.name || bundled_header&.name || theme[:name].to_s.titleize
      theme[:installed_version] = installed_header&.version
      theme[:bundled_version]   = bundled_header&.version
      theme[:status]            = bundled_path ? ThemeInspector.status(bundled_path: bundled_path, installed_path: installed_path) : :custom
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
    theme_name = params[:id]
    source_file = THEMES_DIR.join("#{theme_name}.css")
    dest_file = USER_THEME_DIR.join("#{theme_name}.css")

    # Theme must exist in at least one location to be activatable.
    unless source_file.exist? || dest_file.exist?
      flash[:error] = "Theme '#{theme_name}' not found in app/themes/ or /site/theme/"
      redirect_to admin_themes_path and return
    end

    # First-time activation: install the bundled copy into the user's
    # theme folder so it's editable. If the theme is already there (was
    # edited, copied, or hand-created), leave it untouched.
    message = if dest_file.exist?
      "#{theme_name.capitalize} theme activated"
    else
      FileUtils.mkdir_p(USER_THEME_DIR)
      FileUtils.cp(source_file, dest_file)
      "#{theme_name.capitalize} theme installed and activated"
    end

    update_active_theme(theme_name)
    flash[:notice] = message
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

    if reset_type == "overwrite"
      # Overwrite the installed file with the bundled file. This serves
      # two callers: "reset to original" from the edit page, and "update
      # to bundled version" from the themes index when a newer bundled
      # version is detected. Redirect target depends on which one — back
      # to the index when there's a version-update context, otherwise
      # back to the edit page so the user can keep editing.
      dest_file = USER_THEME_DIR.join("#{theme_name}.css")
      old_header = ThemeInspector.parse_header(dest_file) if dest_file.exist?
      FileUtils.cp(source_file, dest_file)
      new_header = ThemeInspector.parse_header(dest_file)

      if old_header && new_header && old_header.version != new_header.version
        flash[:notice] = "#{theme_name.capitalize} theme updated from v#{old_header.version} to v#{new_header.version}."
        redirect_to admin_themes_path
      else
        flash[:notice] = "#{theme_name.capitalize} theme reset to original. Your customizations have been overwritten."
        redirect_to edit_admin_theme_path(theme_name)
      end
    elsif reset_type == "fresh"
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
    elsif reset_type == "preserve_and_update"
      # Driven from the "Update available" flow on the themes index when
      # the user wants the new bundled version BUT also wants to keep
      # their existing customizations. Renames the user's installed
      # file to a new custom name, rewrites its `Roe Theme:` header so
      # ThemeInspector permanently classifies it as a custom theme (no
      # future update nags), then installs the bundled version at the
      # original filename. Net effect after this action: original
      # filename now holds clean bundled v{new}; the user's prior work
      # lives on at the chosen custom name as an untracked theme.
      installed_file = USER_THEME_DIR.join("#{theme_name}.css")
      unless installed_file.exist?
        flash[:error] = "Theme '#{theme_name}' is not installed."
        redirect_to admin_themes_path and return
      end

      # `custom_name` is treated as the human-readable display name
      # (spaces and mixed case allowed, matching what `Roe Theme:`
      # headers conventionally look like). The filename slug is
      # derived from it via `parameterize`, which handles spaces,
      # periods (so "Default v0.9.0" → "default-v0-9-0"), case, and
      # punctuation in one shot. Internal whitespace runs are
      # collapsed first so a value pasted with line breaks or extra
      # spaces still produces a clean header line.
      display_name = (custom_name.presence || "#{theme_name.capitalize} preserved")
                       .gsub(/\s+/, " ").strip
      preserve_slug = display_name.parameterize

      if preserve_slug.blank?
        flash[:error] = "Custom name must contain at least one letter or number."
        redirect_to admin_themes_path and return
      end

      if preserve_slug == theme_name
        flash[:error] = "Custom name cannot resolve to the same filename as the original theme."
        redirect_to admin_themes_path and return
      end

      preserved_file = USER_THEME_DIR.join("#{preserve_slug}.css")
      if preserved_file.exist?
        flash[:error] = "A theme file named '#{preserve_slug}.css' already exists. Please choose a different name."
        redirect_to admin_themes_path and return
      end

      # Save the customized file under its new name with a rewritten
      # `Roe Theme:` header first — so even if the bundled cp below
      # somehow fails, the user's work is already on disk under the
      # preserved filename. Only `.sub` (not `gsub`) on the header to
      # avoid mangling any later occurrences in CSS comments.
      content = File.read(installed_file)
      rewritten = content.sub(/^(\s*Roe Theme:\s*).+$/) { "#{Regexp.last_match(1)}#{display_name}" }
      File.write(preserved_file, rewritten)

      FileUtils.cp(source_file, installed_file)

      bundled_version = ThemeInspector.parse_header(source_file)&.version
      flash[:notice] = "Saved your customized #{theme_name.capitalize} theme as '#{display_name}' " \
                       "(#{preserve_slug}.css, now a custom theme) and installed bundled v#{bundled_version} as #{theme_name.capitalize}."
      redirect_to admin_themes_path
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
    Dir.glob(THEMES_DIR.join("*.css")).each do |file|
      name = File.basename(file, ".css")
      themes[name] = {
        name: name,
        path: file,
        size: File.size(file),
        master: true
      }
    end

    # Then, add user themes from /site/theme/ that aren't already listed
    Dir.glob(USER_THEME_DIR.join("*.css")).each do |file|
      name = File.basename(file, ".css")
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
    return "default" unless File.exist?(site_file)

    config = YAML.safe_load_file(site_file, permitted_classes: [ Date, Time, Symbol ]) || {}
    config.dig("theme", "active") || "default"
  end

  def update_active_theme(theme_name)
    site_file = SiteConfig::SITE_FILE

    # Read existing config
    config = if File.exist?(site_file)
      YAML.safe_load_file(site_file, permitted_classes: [ Date, Time, Symbol ]) || {}
    else
      {}
    end

    # Update theme
    config["theme"] ||= {}
    config["theme"]["active"] = theme_name

    # Write back to file (preserving structure)
    File.write(site_file, config.to_yaml)

    # Sync to database and clear cache
    SiteConfig.sync_from_file("site")
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

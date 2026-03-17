class Admin::ConfigsController < ApplicationController
  layout 'application'

  # Site Config Schema Definition
  SITE_CONFIG_SCHEMA = {
    site_info: {
      label: "Site Information",
      fields: {
        'title' => {
          type: :text,
          label: 'Site Title',
          required: true,
          hint: 'Used in page titles, feeds, and site header'
        },
        'description' => {
          type: :textarea,
          label: 'Site Description',
          rows: 3,
          hint: 'Used in meta tags and RSS/Atom feeds'
        },
        'author' => {
          type: :text,
          label: 'Author Name',
          hint: 'Default author for posts and pages'
        }
      }
    },

    branding: {
      label: "Branding",
      fields: {
        'logo' => {
          type: :text,
          label: 'Logo Image Path',
          hint: 'Copy logo url from Global Images.'
        },
        'logo_style' => {
          type: :select,
          label: 'Logo Style',
          options: [ 'beside_text', 'replace_text' ],
          depends_on: "logo",
          hint: "How the logo should be displayed"
        },
        'favicon' => {
          type: :text,
          label: 'Favicon',
          hint: 'Copy logo url from Global Images.',
          placeholder: "favicon.ico"
        }
      }
    },

    fonts: {
      label: "Custom Fonts",
      help_text: "Upload font files with the Fonts button and copy url…",
      type: :font_roles,
      # Fixed roles with flexible variants
      roles: {
        heading: {
          label: "Heading Font",
          description: "Used for all headings (h1-h6)",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic', 'light', 'medium', 'semibold', 'black' ]
        },
        body: {
          label: "Body Font",
          description: "Used for paragraphs and body text",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic', 'light', 'medium', 'semibold' ]
        },
        mono: {
          label: "Monospace Font",
          description: "Used for code blocks and preformatted text",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic' ]
        }
      }
    }
  }.freeze

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
    @config_schema = SITE_CONFIG_SCHEMA
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

    config_name = type.split('/').last.capitalize
    flash[:notice] = "#{config_name} configuration updated successfully"

    # Redirect back to the appropriate edit page
    case type
    when 'site'
      redirect_to admin_edit_site_config_path
    when 'defaults/cards'
      redirect_to admin_edit_cards_config_path
    when 'defaults/collections'
      redirect_to admin_edit_collections_config_path
    else
      redirect_to admin_configs_path
    end
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type = type.split('/').last
    @config_content = content
    render :edit
  end
end

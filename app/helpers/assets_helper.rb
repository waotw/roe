module AssetsHelper
  def font_face_css
    fonts_config = SiteConfig.get('fonts')

    css = []

    # Generate @font-face rules for each font role (only if fonts are configured)
    if fonts_config
      %w[heading body mono].each do |role|
        next unless fonts_config[role]

        font_data = fonts_config[role]
        family = font_data['family']

        # Generate rule for each variant
        generate_font_face(css, family, font_data['regular'], 400, 'normal') if font_data['regular']
        generate_font_face(css, family, font_data['bold'], 700, 'normal') if font_data['bold']
        generate_font_face(css, family, font_data['italic'], 400, 'italic') if font_data['italic']
        generate_font_face(css, family, font_data['bold_italic'], 700, 'italic') if font_data['bold_italic']
      end
    end

    # Generate CSS variables for fonts and assets
    css << "\n:root {"
    css << "  --font-heading: #{font_stack('heading', fonts_config)};"
    css << "  --font-body: #{font_stack('body', fonts_config)};"
    css << "  --font-mono: #{font_stack('mono', fonts_config)};"
    css << asset_variables
    css << "}"

    css.join("\n")
  end

  def asset_variables
    vars = []

    # Logo
    logo_url = SiteConfig.get('logo')

    # Only process logo if it exists and is not 'none'
    if logo_url.present? && logo_url != 'none'
      logo_style = SiteConfig.get('logo_style')

      # If it starts with /, use it as-is (media file), otherwise treat as system asset
      logo_path = if logo_url.start_with?('/')
        logo_url
      else
        system_image_path(logo_url)
      end

      vars << "  --logo-url: url('#{logo_path}');"

      # Only add logo-style if it's set
      if logo_style.present?
        vars << "  --logo-style: #{logo_style};"
      end
    end

    vars.join("\n")
  end

  def font_format_for_preload(filename)
    case File.extname(filename)
    when '.woff2' then 'woff2'
    when '.woff' then 'woff'
    when '.ttf' then 'ttf'
    when '.otf' then 'otf'
    end
  end

  private

  def generate_font_face(css, family, filename, weight, style)
    css << <<~CSS
      @font-face {
        font-family: "#{family}";
        src: url('#{system_font_path(filename)}') format('#{font_format(filename)}');
        font-weight: #{weight};
        font-style: #{style};
        font-display: swap;
      }
    CSS
  end

  def font_format(filename)
    case File.extname(filename)
    when '.woff2' then 'woff2'
    when '.woff' then 'woff'
    when '.ttf' then 'truetype'
    when '.otf' then 'opentype'
    end
  end

  def font_stack(role, fonts_config)
    if fonts_config && fonts_config[role] && fonts_config[role]['family']
      custom = "\"#{fonts_config[role]['family']}\""
      fallback = default_fallback(role)
      "#{custom}, #{fallback}"
    else
      default_fallback(role)
    end
  end

  def default_fallback(role)
    case role
    when 'heading' then 'Georgia, serif'
    when 'body' then 'system-ui, -apple-system, sans-serif'
    when 'mono' then 'Monaco, Consolas, monospace'
    end
  end
end

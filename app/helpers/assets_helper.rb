module AssetsHelper
  def font_face_css
    # Get fonts config - this returns the whole fonts.yml content
    fonts_data = SiteConfig.fonts

    # Extract the 'fonts' key if it exists, otherwise use the data as-is
    fonts_config = fonts_data.is_a?(Hash) ? (fonts_data['fonts'] || fonts_data) : nil

    css = []

    # Generate @font-face rules for each font role (only if fonts are configured)
    if fonts_config
      %w[heading body mono accent].each do |role|
        next unless fonts_config[role]

        font_data = fonts_config[role]
        family = font_data['family']
        next unless family # Skip if no family is defined

        # Generate @font-face rule for each variant dynamically
        font_data.each do |variant_name, filename|
          next if variant_name == 'family' # Skip the family key itself
          next unless filename.present? # Skip empty variants

          # Map variant names to font-weight and font-style
          weight, style = variant_to_weight_style(variant_name)
          generate_font_face(css, family, filename, weight, style)
        end
      end
    end

    # Generate CSS variables for fonts and assets
    css << "\n:root {"
    css << "  --font-heading: #{font_stack('heading', fonts_config)};"
    css << "  --font-body: #{font_stack('body', fonts_config)};"
    css << "  --font-mono: #{font_stack('mono', fonts_config)};"
    css << "  --font-accent: #{font_stack('accent', fonts_config)};"
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

  # Map variant names to CSS font-weight and font-style values
  def variant_to_weight_style(variant_name)
    case variant_name.to_s.downcase
    when 'regular', 'normal'
      [400, 'normal']
    when 'bold'
      [700, 'normal']
    when 'italic'
      [400, 'italic']
    when 'bold_italic', 'bolditalic'
      [700, 'italic']
    when 'light'
      [300, 'normal']
    when 'light_italic', 'lightitalic'
      [300, 'italic']
    when 'medium'
      [500, 'normal']
    when 'medium_italic', 'mediumitalic'
      [500, 'italic']
    when 'semibold'
      [600, 'normal']
    when 'semibold_italic', 'semibolditalic'
      [600, 'italic']
    when 'black', 'heavy'
      [900, 'normal']
    when 'black_italic', 'blackitalic', 'heavy_italic'
      [900, 'italic']
    when 'thin'
      [100, 'normal']
    when 'thin_italic', 'thinitalic'
      [100, 'italic']
    when 'extralight', 'extra_light'
      [200, 'normal']
    when 'extralight_italic', 'extra_light_italic'
      [200, 'italic']
    when 'extrabold', 'extra_bold'
      [800, 'normal']
    when 'extrabold_italic', 'extra_bold_italic'
      [800, 'italic']
    else
      # Default fallback for unknown variants - assume normal weight/style
      [400, 'normal']
    end
  end

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
    when 'accent' then 'Georgia, serif'
    end
  end
end

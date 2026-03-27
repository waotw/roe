class StaticSiteMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    # Only intercept GET requests for public site (not admin/system)
    if request.get? && !request.path.start_with?('/admin', '/system', '/rails') && static_mode?
      static_path = find_static_file(request.path)

      # Serve static file if it exists
      if static_path && File.exist?(static_path)
        return [
          200,
          {
            'Content-Type' => 'text/html; charset=utf-8',
            'Cache-Control' => 'public, max-age=3600'
          },
          [File.read(static_path)]
        ]
      end
    end

    # Fall through to Rails (dynamic rendering or admin)
    @app.call(env)
  end

  private

  def static_mode?
    # Use existing static_generation_enabled flag
    SiteConfig.current('site')&.static_generation_enabled || false
  rescue
    false # Fail safely if SiteConfig not available
  end

  def find_static_file(path)
    base_path = Rails.root.join('public')

    # Root path
    if path == '/'
      candidate = base_path.join('index.html')
      return candidate.to_s if File.exist?(candidate)
    end

    # Clean path (remove leading slash)
    clean_path = path.sub(/^\//, '')

    # Try exact path with .html
    candidate = base_path.join("#{clean_path}.html")
    return candidate.to_s if File.exist?(candidate)

    # Try as directory with index.html
    candidate = base_path.join(clean_path, 'index.html')
    return candidate.to_s if File.exist?(candidate)

    nil
  end
end

Rails.application.config.middleware.use StaticSiteMiddleware

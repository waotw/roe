# Redirects old URLs to new ones, from site/system/global/redirects.yml.
#
# Roe had no way to answer a URL it used to serve. Two cases where that costs
# real traffic:
#
#   * A same-domain move onto Roe. Substack serves posts at /p/<slug> and Roe
#     at /posts/<slug>; the importer rewrites that inside imported content, but
#     nothing reaches the links pointing in from outside — search results, other
#     people's sites, newsletters already sent.
#   * Renaming a url_name, which Roe treats as routine and which silently breaks
#     every existing link to that page.
#
# Runs ahead of StaticSiteMiddleware so a redirect is answered whether the site
# is served dynamically or from the static build, and before Rails routing so a
# redirect can shadow a path Roe would otherwise 404.
#
# Deliberately small: exact paths and a single trailing /* prefix. Regex rules
# and per-rule conditions are where redirect config usually grows into something
# nobody can debug from a YAML file.
class SiteRedirectsMiddleware
  # Built from RoeSitePaths, not SiteConfig: middleware is constructed during
  # boot, before app models are autoloadable.
  CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "global", "redirects.yml")

  # Roe's own paths are never redirectable — a typo in redirects.yml shouldn't
  # be able to lock someone out of the admin that would let them fix it.
  PROTECTED_PREFIXES = %w[/admin /system /rails /webhooks /api].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless request.get? || request.head?
    return @app.call(env) if protected?(request.path)

    if (rule = match(request.path))
      return redirect(rule, request)
    end

    @app.call(env)
  end

  class << self
    # Parsed rules, cached until the file changes. Each is
    # { prefix:, exact:, to:, status: }.
    def rules
      mtime = File.exist?(CONFIG_PATH) ? File.mtime(CONFIG_PATH) : nil
      return @rules if defined?(@rules) && @cached_mtime == mtime

      @cached_mtime = mtime
      @rules = load_rules
    end

    # Not an endless def with a modifier-if: that parses as conditionally
    # DEFINING the method, and @rules is never set at class-definition time.
    def reload!
      remove_instance_variable(:@rules) if defined?(@rules)
      remove_instance_variable(:@cached_mtime) if defined?(@cached_mtime)
    end

    private

    def load_rules
      return [] unless File.exist?(CONFIG_PATH)

      raw = YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [], aliases: false) || {}
      return [] unless raw.is_a?(Hash)

      # Nested under `redirects:` to match every other file in system/global/,
      # which are all maps of named top-level keys — and so a later setting can
      # be added alongside without it being mistaken for a path.
      rules = raw["redirects"]
      return [] unless rules.is_a?(Hash)

      rules.filter_map { |from, target| build_rule(from, target) }
    rescue Psych::Exception => e
      # A broken redirects file must not take the site down with it.
      Rails.logger.error "[SiteRedirects] redirects.yml is not valid YAML (#{e.message}) — no redirects applied"
      []
    end

    def build_rule(from, target)
      to, status = case target
      when String then [ target, 301 ]
      when Hash   then [ target["to"], (target["status"] || 301).to_i ]
      end
      return nil if from.blank? || to.blank?

      from = from.to_s
      wildcard = from.end_with?("/*")

      {
        # "/p/*" matches /p/anything, capturing the rest WITH its leading slash,
        # so a target needs no trailing slash and can't grow a double one.
        prefix: wildcard ? from.delete_suffix("/*") : nil,
        exact:  wildcard ? nil : from.chomp("/"),
        to:     to.to_s,
        status: [ 301, 302, 307, 308 ].include?(status) ? status : 301
      }
    end
  end

  private

  def protected?(path)
    PROTECTED_PREFIXES.any? { |p| path == p || path.start_with?("#{p}/") }
  end

  def match(path)
    normalized = path.chomp("/")
    normalized = "/" if normalized.empty?

    self.class.rules.find do |rule|
      if rule[:prefix]
        path.start_with?("#{rule[:prefix]}/") || normalized == rule[:prefix]
      else
        normalized == rule[:exact]
      end
    end
  end

  def redirect(rule, request)
    location = rule[:to].dup

    if rule[:prefix]
      # Everything after the prefix, leading slash included.
      remainder = request.path.sub(/\A#{Regexp.escape(rule[:prefix])}/, "")
      location += remainder unless remainder.empty? || remainder == "/"
    end

    # Git asks for /roe.git/info/refs?service=git-upload-pack — drop the query
    # and it gets a dumb-protocol answer and fails. Nothing else needs the
    # query preserved either, but plenty of things break without it.
    location += "?#{request.query_string}" if request.query_string.present?

    # A rule whose target is its own prefix ("/blog/*" → "/blog") sends every
    # request straight back to itself, and a browser gives up with a redirect
    # loop rather than showing the page. Serve normally instead: a mistake in
    # redirects.yml should cost the redirect, not the URL.
    if location == request.fullpath
      Rails.logger.warn "[SiteRedirects] #{request.fullpath} redirects to itself — rule ignored"
      return @app.call(request.env)
    end

    [ rule[:status], { "Location" => location, "Content-Type" => "text/html" }, [ "" ] ]
  end
end

# Appended, not inserted before StaticSiteMiddleware by name — that constant
# doesn't exist yet, because initializers load alphabetically and this file
# sorts first. Appending from here lands ahead of it for the same reason, which
# is a coincidence of filenames rather than a guarantee, so the order is pinned
# by a test (site_redirects_test.rb) instead of left to chance.
Rails.application.config.middleware.use SiteRedirectsMiddleware

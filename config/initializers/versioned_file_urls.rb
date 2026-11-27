# Adds ?v=<version> to every URL of a file Roe serves from disk (/media/,
# /system/images/, /system/fonts/, /theme/, /javascript/) in the public
# site's HTML, at the moment the page is sent. The version changes whenever
# the file does (FileVersions), so the browser can keep each file for a year
# (FileValidators, on live) and still fetches a replaced image, a saved
# stylesheet or a new font straight away: its URL is new.
#
# Done on the finished page rather than wherever a URL is written: one place
# covers Markdown images, variants and srcset, players, @font-face, the
# theme link, og:image and anything added later, and a page that didn't
# change still gets new versions when only a file it shows did.
#
# Left alone:
#   - /admin pages: the admin's own scripts read URLs out of the page (the
#     media picker, the editors), and a ?v= must never end up in content.
#   - Static mode: StaticSiteMiddleware answers before this runs. Its files
#     are copies made by the static build, so a version worked out from
#     site/ could describe a file the copy doesn't have yet.
#   - Feeds, JSON and email: not text/html, or never sent through here.
#     Podcast apps can download an episode again when its URL changes.
#   - URLs inside <script> and in text (code samples in documentation).
class VersionedFileUrls
  SKIP_PREFIXES = %w[/admin /rails /webhooks /api].freeze
  FILE_PATH = %r{/(?:media|system/images|system/fonts|theme|javascript)/}

  URL_ATTRIBUTES = %w[src href poster content data-src data-audio data-image data-cover].freeze
  TOKEN = /
    (<script\b[^>]*>)(.*?)(<\/script\s*>)    # 1-3: a script; only its tag is read
    | (<style\b[^>]*>)(.*?)(<\/style\s*>)    # 4-6: a style block
    | (<[a-zA-Z][^>]*>)                      # 7: any other opening tag
  /mix
  ATTRIBUTE = /(\s(?:#{URL_ATTRIBUTES.join("|")}|srcset|style)\s*=\s*)(["'])(.*?)\2/im
  CSS_URL = /url\(\s*(["']?)([^"')]+)\1\s*\)/i

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    request = Rack::Request.new(env)
    return [ status, headers, body ] unless rewrite?(request, headers)

    html = +""
    body.each { |part| html << part }
    body.close if body.respond_to?(:close)

    rewritten = Rewriter.new([ request.host, site_host ].compact).rewrite(html)
    headers["content-length"] = rewritten.bytesize.to_s if headers["content-length"]
    [ status, headers, [ rewritten ] ]
  end

  private

  # The site's own address from site.yml, which og:image and other absolute
  # URLs are built from; on local it differs from the host being browsed.
  def site_host
    URI.parse(SiteConfig.get("url").to_s.strip).host
  rescue StandardError
    nil
  end

  def rewrite?(request, headers)
    return false unless request.get?
    return false if SKIP_PREFIXES.any? { |p| request.path == p || request.path.start_with?("#{p}/") }

    headers["content-type"].to_s.start_with?("text/html")
  end

  # One page's worth of rewriting. Versions are worked out once per path.
  class Rewriter
    def initialize(hosts)
      @hosts = Array(hosts).map(&:downcase)
      @versions = {}
    end

    def rewrite(html)
      return html unless html.match?(FILE_PATH)

      html.gsub(TOKEN) do
        script_open, script, script_close, style_open, style, style_close, opening = $~.captures
        if script_open then "#{tag(script_open)}#{script}#{script_close}"
        elsif style_open then "#{style_open}#{css(style)}#{style_close}"
        else tag(opening)
        end
      end
    end

    private

    def tag(tag)
      tag.gsub(ATTRIBUTE) do
        name, quote, value = $1, $2, $3
        attribute = name.strip.delete_suffix("=").strip.downcase
        raw = CGI.unescapeHTML(value)
        updated =
          case attribute
          when "srcset" then srcset(raw)
          when "style" then css(raw)
          else versioned(raw)
          end
        updated == raw ? "#{name}#{quote}#{value}#{quote}" : "#{name}#{quote}#{escape(updated, quote)}#{quote}"
      end
    end

    # Escaped for an attribute in the given quotes, and no more: a ' inside
    # "..." stays a ', as it was written.
    def escape(value, quote)
      value.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
           .gsub(quote, quote == '"' ? "&quot;" : "&#39;")
    end

    def srcset(value)
      value.split(",").map do |candidate|
        url, *descriptor = candidate.strip.split(/\s+/)
        [ versioned(url.to_s), *descriptor ].join(" ")
      end.join(", ")
    end

    def css(text)
      text.gsub(CSS_URL) { "url(#{$1}#{versioned($2)}#{$1})" }
    end

    # The URL with ?v= set for its file, or unchanged when it isn't one of
    # Roe's files (or is on another host). Split by hand rather than with
    # URI, which refuses the raw spaces and accents a filename can have, and
    # leaves the rest of the query exactly as written.
    def versioned(url)
      return url unless url.match?(FILE_PATH)

      origin = ""
      rest = url
      if (match = rest.match(%r{\A(?:https?:)?//([^/?#]+)}i))
        return url unless @hosts.include?(match[1].sub(/:\d+\z/, "").downcase)

        origin = match[0]
        rest = rest[match[0].length..]
      end

      rest, fragment = rest.split("#", 2)
      path, query = rest.split("?", 2)
      return url unless path.start_with?(*FileVersions::PREFIXES)

      version = @versions.fetch(path) { @versions[path] = FileVersions.version_for_url(path) }
      return url unless version

      params = query.to_s.split("&").reject { |param| param == "v" || param.start_with?("v=") }
      params << "v=#{version}"
      "#{origin}#{path}?#{params.join("&")}#{"##{fragment}" if fragment}"
    end
  end
end

# Inside StaticSiteMiddleware, so pages it serves from the static build pass
# by untouched (see above).
Rails.application.config.middleware.insert_after StaticSiteMiddleware, VersionedFileUrls

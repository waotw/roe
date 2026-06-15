require "nokogiri"
require "uri"

# Processes user-pasted HTML before it gets rendered into the site
# layout's <head> or just-before-</body> injection points.
#
# Two responsibilities:
#
#   1. Nonce injection. When a CSP is enforced and the page is using
#      nonce-based script/style allowance (Rails sets a per-request
#      nonce via `request.content_security_policy_nonce`), inline
#      <script> and <style> tags from pasted Custom Code need that
#      nonce too or they get blocked. We add it for every inline tag
#      that doesn't already carry one. External `<script src="…">`
#      tags also get the nonce since strict-dynamic CSPs require it
#      for nonce-allowlisted scripts to load their own children.
#
#   2. Hostname extraction. Surfaces every external hostname found
#      in src= / href= attributes so the CSP initializer can add them
#      to script-src / style-src / font-src / img-src allowlists.
#      Currently a soft-deploy: Roe's CSP initializer is commented
#      out, so the extracted hosts are inert. Wired up so that flipping
#      CSP on later doesn't require a second pass through this code.
#
# Output is html_safe (callers can render it directly with <%= %>).
class CustomCodeRenderer
  # Render the user's pasted HTML, injecting the per-request CSP
  # nonce on any inline <script> / <style> tag that doesn't already
  # have one. `nonce` may be nil — when CSP is off, no nonce gets
  # added and the HTML passes through unchanged.
  def self.render(html, nonce: nil)
    return "".html_safe if html.blank?
    return html.html_safe if nonce.blank?

    doc = Nokogiri::HTML.fragment(html)

    # Both inline tags (no src/href) and external script tags benefit
    # from a nonce when strict-dynamic CSP is in play. Existing nonces
    # are left alone so users who paste their own nonce-aware snippets
    # don't get clobbered.
    doc.css("script:not([nonce]), style:not([nonce])").each do |el|
      el["nonce"] = nonce
    end

    doc.to_html.html_safe
  end

  # Pull every external hostname out of pasted HTML. Returns an array
  # of "https://<host>" strings, deduped. Used to expand CSP allowlists
  # so that <script src="https://www.googletagmanager.com/…"> survives
  # an enforced CSP.
  #
  # Skips relative URLs (those go to the same origin, already
  # allowlisted) and unparseable URLs. Always returns https:// even
  # if the source URL was http — modern CSP-aware sites should be
  # HTTPS anywhere, and forcing the upgrade keeps the allowlist tight.
  def self.extract_hosts(*html_chunks)
    hosts = []

    html_chunks.compact.each do |html|
      next if html.blank?

      doc = Nokogiri::HTML.fragment(html)
      doc.css("[src], [href]").each do |el|
        url = el["src"] || el["href"]
        next if url.blank?
        next unless url.start_with?("http")

        host = (URI.parse(url).host rescue nil)
        hosts << "https://#{host}" if host
      end
    end

    hosts.uniq
  end

  # Convenience used by the layout: pulls the configured head_html
  # or footer_html from custom_code.yml and runs it through `render`.
  # Returns "" when:
  #   - custom_code.yml doesn't exist (fresh install before any save)
  #   - the file's `themes:` list doesn't include the currently
  #     active theme (acts as both a theme-specific gate and a
  #     soft kill-switch)
  #   - the field itself is blank
  #
  # Empty `themes:` = active for NO theme. The user has to explicitly
  # check the themes they want the code to load for — matching the
  # natural checkbox semantic ("only what's ticked is on"). To
  # activate on every theme, the user ticks all of them.
  def self.render_field(field_name, nonce: nil)
    config = SiteConfig.custom_code
    return "".html_safe unless config.is_a?(Hash)
    return "".html_safe unless theme_active?(config)

    render(config[field_name].to_s, nonce: nonce)
  end

  # CSP-hook helper: returns the merged list of hosts across both
  # head_html and footer_html. Intended to be called from a proc in
  # config/initializers/content_security_policy.rb. Respects the
  # theme scoping the same way render_field does — hosts only get
  # allowlisted when the code is actually going to render.
  def self.allowlist_hosts
    config = SiteConfig.custom_code
    return [] unless config.is_a?(Hash)
    return [] unless theme_active?(config)

    extract_hosts(config["head_html"], config["footer_html"])
  end

  # True when the currently active theme is in custom_code.yml's
  # `themes:` list. Used by both render_field and allowlist_hosts
  # so the gate logic stays in one place.
  def self.theme_active?(config)
    scoped_themes = Array(config["themes"])
    return false if scoped_themes.empty?

    active_theme = SiteConfig.get("theme.active") || "default"
    scoped_themes.include?(active_theme)
  end
end

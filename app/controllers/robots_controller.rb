# frozen_string_literal: true

# /robots.txt for a dynamically served site.
#
# Roe wrote one only for static builds, and it said `Allow: /` to everyone —
# so a self-hosted site had no opt-out to honour even from the crawlers that
# would have honoured one. What's served here comes from the same AiCrawlers
# source the static generator uses, so the two can't disagree.
class RobotsController < ApplicationController
  skip_before_action :require_authentication

  def show
    render plain: AiCrawlers.robots_txt(sitemap_url: sitemap_url),
           content_type: "text/plain"
  end

  private

  # Only static builds produce a sitemap.xml; pointing at one that isn't there
  # is worse than saying nothing.
  def sitemap_url
    return nil unless SiteConfig.get("static_generation_enabled")

    base = SiteConfig.get("url").to_s.strip
    base.present? ? "#{base.chomp('/')}/sitemap.xml" : nil
  end
end

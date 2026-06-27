# Composes per-page SEO metadata (title, description, OpenGraph,
# Twitter Cards, canonical URL, JSON-LD) for the public site layout.
#
# Auto-detects the "subject" of the page from the standard ivars set
# by the show controllers — @post, @page (when it's a Page record,
# not the pagination integer used by collections), @product, @doc —
# and composes tags from each subject's metadata with fallbacks to
# the site-wide config.
#
# Render via the shared/_head_meta partial; controllers don't need to
# do anything special — the helper finds what it needs in the view
# context.
module SeoHelper
  # The CMS content record being rendered, if any. Returns nil for
  # collection pages (@page is an integer there) and for any future
  # listing/index page.
  def seo_subject
    candidates = [
      instance_variable_get(:@post),
      instance_variable_get(:@doc),
      instance_variable_get(:@product),
      instance_variable_get(:@page)
    ]
    candidates.find do |obj|
      obj.is_a?(Post) || obj.is_a?(Page) || obj.is_a?(Product) || obj.is_a?(Documentation)
    end
  end

  # Page title for <title> and og:title. Composes "{thing} — {site}"
  # where {thing} is the subject's title, the collection heading, or
  # nothing (homepage). Falls back to bare site title.
  def seo_title
    site = SiteConfig.get("title").presence
    page = seo_page_title

    return page if site.blank?
    return site if page.blank? || page == site
    "#{page} — #{site}"
  end

  # Description for <meta name="description">, og:description,
  # twitter:description. Fallback chain: subject excerpt → subject
  # subtitle → collection description → site description.
  def seo_description
    if (subject = seo_subject)
      excerpt = subject.metadata["excerpt"].to_s.strip.presence
      return excerpt if excerpt

      subtitle = subject.metadata["subtitle"].to_s.strip.presence
      return subtitle if subtitle
    elsif (collection_desc = instance_variable_get(:@page_description).to_s.strip.presence)
      return collection_desc
    end

    SiteConfig.get("description").to_s.strip.presence
  end

  # author for <meta name="author"> and article:author. Subject's
  # author override → site-wide author.
  def seo_author
    subject_author = seo_subject&.metadata&.dig("author").to_s.strip.presence
    subject_author || SiteConfig.get("author").to_s.strip.presence
  end

  # Absolute URL for og:image / twitter:image.
  #
  # Default fallback chain (first non-nil, non-SVG wins):
  #   post/page/product metadata["social_image"]   ← per-post override
  #   post/page/product metadata["image"]          ← hero/featured
  #   site social_image
  #   site logo
  #
  # When social_image_override is true in site.yml, the site
  # social_image takes precedence over any per-post image — gives
  # consistent brand presence across all shared links.
  #
  # SVG files are skipped at every step: Twitter/Facebook crawlers
  # silently reject `image/svg+xml` images for cards, so falling
  # through to the next candidate avoids a broken-looking unfurl.
  #
  # Returns nil rather than emitting a broken tag when nothing is set.
  def seo_image_url
    social_image   = SiteConfig.get("social_image").to_s.strip.presence
    override       = SiteConfig.get("social_image_override")
    use_override   = override == true || override == "true"

    chain = if use_override && social_image.present? && !svg?(social_image)
      [ social_image, SiteConfig.get("logo").to_s.strip.presence ]
    else
      [
        seo_subject&.metadata&.dig("social_image").to_s.strip.presence,
        seo_subject&.metadata&.dig("image").to_s.strip.presence,
        social_image,
        SiteConfig.get("logo").to_s.strip.presence
      ]
    end

    candidate = chain.compact.find { |c| !svg?(c) }
    return nil if candidate.blank?
    absolutize(candidate)
  end

  # Pixel dimensions of seo_image_url's source file. Returned shape
  # is { width:, height: }, or nil when the image is remote-hosted,
  # missing, or an unsupported format. Used by og:image:width /
  # og:image:height — Twitter / Facebook crawlers downgrade or skip
  # `summary_large_image` cards when these tags are missing OR when
  # the declared dimensions don't match what the crawler measures.
  def seo_image_dimensions
    return nil unless seo_image_url
    ImageDimensions.for_url(raw_seo_image_path)
  end

  # Alt text for og:image:alt / twitter:image:alt.
  # Fallback: post/page/product metadata["image_alt"] → site
  # social_image_alt → subject title → site title. Falls through
  # rather than emitting a tag with nothing meaningful in it.
  def seo_image_alt
    candidate =
      seo_subject&.metadata&.dig("image_alt").to_s.strip.presence ||
      SiteConfig.get("social_image_alt").to_s.strip.presence ||
      (seo_subject&.respond_to?(:title) && seo_subject.title.to_s.strip.presence) ||
      SiteConfig.get("title").to_s.strip.presence
    candidate
  end

  # Twitter card type — "summary_large_image" (wide banner above the
  # title) vs "summary" (small square thumb beside the title). Picked
  # from the social image's aspect ratio:
  #   square-ish (0.8–1.25)  → summary       — logos / brand marks
  #   wider or taller        → summary_large_image
  # When we have no image, or can't measure it (remote-hosted), default
  # to summary_large_image — that's the existing behaviour and the
  # right call for the common case of a 1200×630 social image.
  SQUARE_RATIO_MIN = 0.8
  SQUARE_RATIO_MAX = 1.25

  def seo_twitter_card_type
    return "summary" unless seo_image_url
    dims = seo_image_dimensions
    return "summary_large_image" unless dims && dims[:height].to_i.positive?

    ratio = dims[:width].to_f / dims[:height]
    ratio.between?(SQUARE_RATIO_MIN, SQUARE_RATIO_MAX) ? "summary" : "summary_large_image"
  end

  # Twitter @handle for twitter:site. Stripped to remove a leading
  # "@" if the user added one, then re-added — keeps emission
  # consistent regardless of how the field was filled in.
  def seo_twitter_handle
    raw = SiteConfig.get("twitter_handle").to_s.strip
    return nil if raw.empty?
    handle = raw.sub(/\A@/, "")
    "@#{handle}"
  end

  private

  def svg?(path)
    path.to_s.downcase.end_with?(".svg")
  end

  # Recompute the same chain seo_image_url uses, but return the raw
  # source path (NOT absolutized) so ImageDimensions can map it back
  # to the filesystem. Kept separate from seo_image_url because the
  # consumer there needs a URL while the consumer here needs the path.
  def raw_seo_image_path
    social_image   = SiteConfig.get("social_image").to_s.strip.presence
    override       = SiteConfig.get("social_image_override")
    use_override   = override == true || override == "true"

    chain = if use_override && social_image.present? && !svg?(social_image)
      [ social_image, SiteConfig.get("logo").to_s.strip.presence ]
    else
      [
        seo_subject&.metadata&.dig("social_image").to_s.strip.presence,
        seo_subject&.metadata&.dig("image").to_s.strip.presence,
        social_image,
        SiteConfig.get("logo").to_s.strip.presence
      ]
    end

    chain.compact.find { |c| !svg?(c) }
  end

  public

  # Canonical URL — the absolute version of request.path. We strip
  # query strings because pagination/filter variants are typically
  # not what we want crawlers indexing as duplicates (collections
  # being the exception, handled below).
  def seo_canonical_url
    full_site_url + request.path
  end

  # Site URL with protocol. Uses SiteConfig.site_url when it's set to
  # something real, otherwise falls back to request.base_url. The
  # fallback handles the common case where a user spins up Roe locally
  # or on a new server without setting `url:` in site.yml yet.
  def full_site_url
    configured = SiteConfig.site_url.to_s
    if configured.include?("localhost") || configured.match?(/^https?:\/\/127\./)
      request.base_url
    else
      configured
    end
  end

  # og:type — "article" for posts (including podcast episodes),
  # "product" for store items, "website" for everything else
  # (pages, collections, homepage).
  def seo_og_type
    case seo_subject
    when Post    then "article"
    when Product then "product"
    else "website"
    end
  end

  # Whether to emit <meta name="robots" content="noindex">. Three
  # cases:
  #   1. The subject's `status: unlisted` — admin published it but
  #      doesn't want it crawled / surfaced in feeds.
  #   2. We're in theme preview mode — admin-authenticated theme
  #      previews shouldn't be indexed even if a crawler somehow got
  #      the URL.
  #   3. Any explicit ?preview=… or ?preview_theme=… in params, as
  #      belt-and-suspenders against future preview flavours.
  def seo_noindex?
    return true if instance_variable_get(:@preview_mode)
    return true if params[:preview_theme].present? || params[:preview].present?

    status = seo_subject&.metadata&.dig("status")
    status == "unlisted"
  end

  # ISO 8601 publication time for article:published_time and
  # JSON-LD datePublished. Returns nil if missing or unparseable.
  def seo_published_time
    raw = seo_subject&.metadata&.dig("date")
    return nil if raw.blank?

    Time.zone.parse(raw.to_s).iso8601
  rescue ArgumentError
    nil
  end

  # article:tag emit list. Tags is conventionally a comma-separated
  # string in Roe metadata; split + trim + drop blanks.
  def seo_tags
    raw = seo_subject&.metadata&.dig("tags").to_s
    raw.split(",").map(&:strip).reject(&:blank?)
  end

  # JSON-LD Article schema for posts. Returns a Hash; the caller is
  # responsible for `.to_json.html_safe`-ing it into a <script> tag.
  # Returns nil if the subject isn't a Post (no schema for the
  # homepage / pages / products — those can get their own schemas
  # later if it becomes valuable).
  def article_jsonld
    return nil unless seo_subject.is_a?(Post)

    {
      "@context"      => "https://schema.org",
      "@type"         => "Article",
      "headline"      => seo_page_title,
      "description"   => seo_description,
      "image"         => seo_image_url,
      "datePublished" => seo_published_time,
      "author"        => seo_author.present? ? { "@type" => "Person", "name" => seo_author } : nil,
      "publisher"     => seo_publisher_jsonld,
      "mainEntityOfPage" => {
        "@type" => "WebPage",
        "@id"   => seo_canonical_url
      }
    }.compact
  end

  # Per-podcast RSS auto-discovery — emit a <link rel="alternate">
  # pointing at the podcast's feed when the subject is a podcast
  # episode that's wired up to a podcast key in podcast.yml.
  def podcast_feed_link
    return nil unless seo_subject.is_a?(Post)
    return nil unless seo_subject.post_type == "podcast"

    podcast_key = seo_subject.metadata["podcast"].to_s.strip
    return nil if podcast_key.blank?

    podcast = PodcastConfig.get(podcast_key)
    return nil unless podcast

    {
      href:  podcast_feed_url(podcast_key: podcast_key),
      title: "#{podcast['title']} feed"
    }
  end

  private

  # The "page" half of the {page} — {site} title. Different per page
  # type:
  #   - Subject record: the record's title
  #   - Collection page: @page_heading with HTML stripped (the
  #     controller composes things like
  #     "<span class='collection-context'>(X)</span>" into it)
  #   - Anything else (homepage): nil → falls through to bare site
  #     title in seo_title.
  def seo_page_title
    if (subject = seo_subject)
      subject.metadata["title"].to_s.strip.presence
    elsif (heading = instance_variable_get(:@page_heading))
      strip_tags(heading).to_s.strip.presence
    end
  end

  # Resolve a metadata image reference into an absolute URL.
  # Recognises three forms:
  #   1. Full URL — return as-is
  #   2. Root-relative path (/media/images/x.jpg, /system/images/x.jpg)
  #      — prefix with site URL
  #   3. Bare filename (logo.png) — assume it lives under
  #      /site/system/assets/images/ (where social_image, logo, and
  #      favicon all live) and build a /system/images/ URL.
  def absolutize(path)
    return path if path.match?(/\Ahttps?:\/\//)
    return full_site_url + path if path.start_with?("/")
    "#{full_site_url}/system/images/#{path}"
  end

  # Publisher block for JSON-LD. Required by Google's Article schema
  # for rich-result eligibility. Uses site title + logo as the
  # organization identity.
  def seo_publisher_jsonld
    logo = SiteConfig.get("logo").to_s.strip.presence
    publisher = {
      "@type" => "Organization",
      "name"  => SiteConfig.get("title").to_s.strip.presence || "Site"
    }
    publisher["logo"] = {
      "@type" => "ImageObject",
      "url"   => absolutize(logo)
    } if logo
    publisher
  end
end

module AdminHelper
  def useful_links
    links = {}

    # Feed URLs — the built-in all-posts feed plus any named feeds from feeds.yml.
    links[:feeds] = {
      "RSS Feed" => feed_path,
      "Atom Feed" => feed_atom_path
    }
    FeedConfig.feed_names.each do |name|
      config = FeedConfig.get(name)
      label = config["title"].presence || name.to_s.titleize
      links[:feeds][label] = named_feed_path(name)
    end

    # Podcast feeds — one per show in podcast.yml. The live public feed is
    # /podcast/<key>.xml; a paid-only show has no public feed, so we point at
    # its private URL instead. (PodcastConfig.feed_url is stale — it names a
    # route that doesn't exist — so build the paths from the routes directly.)
    podcast_feeds = PodcastConfig.podcast_keys.each_with_object({}) do |key, hash|
      config = PodcastConfig.get(key)
      next unless config

      title = config["title"].presence || key.to_s.titleize
      if config["audience"] == "paid"
        hash["#{title} (private)"] = private_podcast_feed_path(key)
      else
        hash[title] = podcast_feed_path(key)
      end
    end
    links[:podcasts] = podcast_feeds if podcast_feeds.any?

    # Published Pages - order by title in metadata JSON
    published_pages = Page.published.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    links[:pages] = published_pages.each_with_object({}) do |page, hash|
      hash[page.title || page.url_name] = "/#{page.url_name}"
    end

    # Member links (if members enabled)
    if members_enabled?
      links[:members] = build_member_links
    end

    # Common paths
    links[:other] = {
      "Home" => root_path,
      "Admin Dashboard" => admin_root_path
    }

    links
  end

  def build_member_links
    member_links = {}

    member_links["Sign Up"] = "/#{find_member_page('signup').url_name}" if find_member_page("signup")
    member_links["Sign In"] = "/#{find_member_page('signin').url_name}" if find_member_page("signin")

    # Upgrade page only when memberships path is enabled and Stripe is hooked up.
    if SiteFeature.memberships_enabled? && stripe_membership_ready?
      upgrade = find_member_page("upgrade")
      member_links["Upgrade to Paid"] = "/#{upgrade.url_name}" if upgrade
    end

    # Donation page only when donations path is enabled. Donations don't
    # need the membership price_id; just a connected Stripe account.
    if SiteFeature.donations_enabled? && StripeConfig.current.connected?
      donate = find_member_page("donate")
      member_links["Support / Donate"] = "/#{donate.url_name}" if donate
    end

    member_links
  end

  private

  # Member-facing pages currently live in two places — site/pages/<name>.md
  # (legacy) and site/pages/members/<name>.md (canonical going forward).
  # Prefer the new location, fall back to the legacy one.
  def find_member_page(stem)
    pages_path = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "pages"))
    [ pages_path.join("members", "#{stem}.md"), pages_path.join("#{stem}.md") ]
      .map { |p| Page.find_by(file_path: p.to_s) }
      .compact
      .first
  end

  def stripe_membership_ready?
    stripe_config = StripeConfig.current
    stripe_config.connected? && stripe_config.price_id.present?
  end
end

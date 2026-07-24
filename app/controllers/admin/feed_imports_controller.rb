# Feed Imports — paste an RSS/Atom URL or an Apple Podcasts link, preview what
# it holds, then import the items as draft posts (articles or podcast episodes)
# via FeedImporter. Fetching is stateless: the feed is re-fetched on the import
# submit rather than stashed, so a token-bearing feed URL never gets persisted.
class Admin::FeedImportsController < Admin::BaseController
  before_action :load_imports, only: [ :index, :preview, :add_show ]

  def index
    @feed_url = ""
  end

  # Summary of a single feed import + its current content breakdown.
  def show
    @import = Import.where(source_type: "feed").find(params[:id])
  end

  # Delete a feed import and its DRAFT episodes/articles; published are kept.
  def destroy
    import = Import.where(source_type: "feed").find(params[:id])
    deleted = import.delete_draft_content!
    kept = import.ref_published_count

    if kept.zero?
      import.destroy
      notice = "Deleted import ##{import.id} and its #{helpers.pluralize(deleted, 'draft')}."
    else
      import.update!(status: :rolled_back)
      notice = "Deleted #{helpers.pluralize(deleted, 'draft')}. " \
               "Kept #{helpers.pluralize(kept, 'published item')} — delete those manually from Posts."
    end
    redirect_to admin_feed_imports_path, notice: notice
  end

  # Fetch + classify, then re-render index with the preview panel.
  def preview
    @feed_url = params[:feed_url].to_s.strip
    if @feed_url.blank?
      flash.now[:alert] = "Paste a feed URL or an Apple Podcasts link."
      return render :index, status: :unprocessable_entity
    end

    result = PodcastFeedFetcher.fetch(@feed_url)
    unless result.success?
      flash.now[:alert] = "Couldn't load that feed: #{result.error}"
      return render :index, status: :unprocessable_entity
    end

    @feed        = result.data
    @channel     = @feed[:channel] || {}
    @composition = FeedImporter.classify(@feed[:items])
    @podcast_options = podcast_options
    @default_podcast_key = matching_podcast_key(@feed)

    if @composition[:total].zero?
      flash.now[:alert] = "That feed has no items to import."
      return render :index, status: :unprocessable_entity
    end

    render :index
  end

  # Seed a new podcast show from this feed's channel (no leaving the page),
  # then re-render the preview with the new show selected so the import can
  # continue. Reuses the same seeder as the Podcasts admin's "Seed from RSS".
  def add_show
    feed_url = params[:feed_url].to_s.strip
    result   = PodcastFeedFetcher.fetch(feed_url)
    unless result.success?
      return redirect_to admin_feed_imports_path, alert: "Couldn't load that feed: #{result.error}"
    end

    channel = (result.data[:channel] || {}).transform_keys(&:to_s)
    title   = params[:podcast_title].presence || channel["title"]
    if title.blank?
      return redirect_to admin_feed_imports_path, alert: "Give the new show a title."
    end
    channel["title"] = title

    key       = PodcastConfigSeeder.derive_key(title)
    subscribe = result.data[:apple_id] ? PodcastAppleLink.subscribe_links(result.data[:apple_id]) : {}
    PodcastConfigSeeder.new(key, channel, mode: :create, subscribe_links: subscribe).seed!
    # seed! only clears the config cache; when a podcast config row already
    # exists (shows already set up) that stale row would hide the new show.
    # Re-read the file into the DB row so the select picks it up this request.
    SiteConfig.sync_from_file("features/podcast")

    @feed_url        = feed_url
    @feed            = result.data
    @channel         = result.data[:channel] || {}
    @composition     = FeedImporter.classify(@feed[:items])
    @podcast_options = podcast_options
    @default_podcast_key = key
    flash.now[:notice] = "Added “#{title}.” Review the options and import below."
    render :index
  end

  # Re-fetch and import. Redirects to the drafts list on success.
  def create
    feed_url    = params[:feed_url].to_s.strip
    kind        = params[:kind].to_s
    podcast_key = params[:podcast_key].presence
    limit       = import_limit

    unless %w[articles episodes].include?(kind)
      return redirect_to admin_feed_imports_path, alert: "Choose whether to import articles or episodes."
    end

    if kind == "episodes" && podcast_key.blank?
      return redirect_to admin_feed_imports_path, alert: "Pick a podcast show for the episodes, or set one up first."
    end

    result = PodcastFeedFetcher.fetch(feed_url)
    unless result.success?
      return redirect_to admin_feed_imports_path, alert: "Couldn't load that feed: #{result.error}"
    end

    import = Import.create!(
      source_type: "feed", phase: 1, status: :importing_posts,
      started_at: Time.current, configuration: { "source" => feed_url_label(feed_url), "kind" => kind }
    )
    outcome = FeedImporter.new(
      feed: result.data, kind: kind.to_sym, podcast_key: podcast_key, limit: limit, import_ref: import.id
    ).import
    import.update!(
      status: :completed, completed_at: Time.current,
      stats: { "imported" => outcome.imported, "skipped" => outcome.skipped, "kind" => kind }
    )

    redirect_to admin_posts_path(status: "draft", sort: "updated-desc"), notice: import_notice(kind, outcome)
  rescue ArgumentError => e
    redirect_to admin_feed_imports_path, alert: e.message
  end

  private

  def load_imports
    @imports = Import.where(source_type: "feed").order(created_at: :desc)
  end

  # A feed URL may carry a paywall token — keep only the host for display.
  def feed_url_label(url)
    URI.parse(url).host || "feed"
  rescue URI::InvalidURIError
    "feed"
  end

  # nil = all; a positive Integer = latest N.
  def import_limit
    return nil unless params[:count_mode] == "latest"
    n = params[:count].to_i
    n.positive? ? n : nil
  end

  def import_notice(kind, outcome)
    noun = kind.singularize
    notice = "Imported #{outcome.imported} #{noun.pluralize(outcome.imported)} as drafts."
    notice += " Skipped #{outcome.skipped} already imported." if outcome.skipped.positive?
    notice
  end

  # Existing podcast shows for the episode select — [title, key] pairs. Empty
  # when the podcast feature is off or no shows are set up yet.
  def podcast_options
    return [] unless SiteFeature.podcast_enabled?
    PodcastConfig.podcast_keys.map { |key| [ PodcastConfig.get(key)["title"].presence || key, key ] }
  end

  # The existing show that this feed belongs to, so it's pre-selected instead
  # of defaulting to whichever show happens to be first. Matched (in priority)
  # by Apple ID, the key its title would derive to, website link, then title.
  def matching_podcast_key(feed)
    return nil unless SiteFeature.podcast_enabled?

    channel  = feed[:channel] || {}
    apple_id = feed[:apple_id].to_s
    link     = normalize_link(channel[:link])
    title    = channel[:title].to_s.strip.downcase
    derived  = PodcastConfigSeeder.derive_key(channel[:title])

    by_apple = by_derived = by_link = by_title = nil
    PodcastConfig.podcast_keys.each do |key|
      cfg = PodcastConfig.get(key) || {}
      by_apple   ||= key if apple_id.present? && PodcastAppleLink.podcast_id(cfg["apple_podcasts"]) == apple_id
      by_derived ||= key if derived.present? && key == derived
      by_link    ||= key if link.present? && normalize_link(cfg["link"]) == link
      by_title   ||= key if title.present? && cfg["title"].to_s.strip.downcase == title
    end
    by_apple || by_derived || by_link || by_title
  end

  def normalize_link(url)
    url.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").sub(/\Awww\./, "").sub(%r{/\z}, "")
  end
end

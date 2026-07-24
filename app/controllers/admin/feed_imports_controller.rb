# Feed Imports — paste an RSS/Atom URL or an Apple Podcasts link, preview what
# it holds, then import the items as draft posts (articles or podcast episodes)
# via FeedImporter. Fetching is stateless: the feed is re-fetched on the import
# submit rather than stashed, so a token-bearing feed URL never gets persisted.
class Admin::FeedImportsController < Admin::BaseController
  def index
    @feed_url = ""
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

    if @composition[:total].zero?
      flash.now[:alert] = "That feed has no items to import."
      return render :index, status: :unprocessable_entity
    end

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

    outcome = FeedImporter.new(
      feed: result.data, kind: kind.to_sym, podcast_key: podcast_key, limit: limit
    ).import

    redirect_to admin_posts_path(status: "draft", sort: "updated-desc"), notice: import_notice(kind, outcome)
  rescue ArgumentError => e
    redirect_to admin_feed_imports_path, alert: e.message
  end

  private

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
end

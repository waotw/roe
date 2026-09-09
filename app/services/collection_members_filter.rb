class CollectionMembersFilter
  def self.filter(items, config = {})
    new(items, config).filter
  end

  def initialize(items, config = {})
    @items = items
    @config = config
  end

  def filter
    apply_paid_content_filter
    # Returns filtered items
    @items
  end

  private

  def apply_paid_content_filter
    return unless SiteConfig.feature_enabled?("members")
    return if should_show_paid?

    # Return early if items is an array (empty collection or already filtered)
    return @items if @items.is_a?(Array)

    @items = hide_paid(@items)
  end

  # Hide paid posts — including ones that are paid only by inheritance.
  #
  # An episode on a paid show carries no audience of its own, so matching the
  # column alone left it in the collection while its audio 403'd. The paid show
  # and release keys are a short list from config, so they go into the query
  # rather than forcing this into Ruby.
  def hide_paid(scope)
    own_free = <<~SQL.squish
      json_extract(metadata, '$.audience') IS NULL
        OR json_extract(metadata, '$.audience') != 'paid'
    SQL

    blank_audience = <<~SQL.squish
      json_extract(metadata, '$.audience') IS NULL
        OR TRIM(json_extract(metadata, '$.audience')) = ''
    SQL

    scope = scope.where(own_free)

    paid_shows = PodcastConfig.paid_keys
    paid_releases = ReleaseConfig.paid_keys
    return scope if paid_shows.empty? && paid_releases.empty?

    # Of the ones that look free, drop any that inherit paid from their
    # container. NOT(blank AND in a paid container) keeps explicit opt-outs.
    inherits_paid = []
    binds = []
    if paid_shows.any?
      inherits_paid << "json_extract(metadata, '$.podcast') IN (?)"
      binds << paid_shows
    end
    if paid_releases.any?
      inherits_paid << "json_extract(metadata, '$.release') IN (?)"
      binds << paid_releases
    end

    scope.where.not(
      [ "(#{blank_audience}) AND (#{inherits_paid.join(' OR ')})", *binds ]
    )
  end

  def should_show_paid?
    # Paid members always see paid content
    return true if @config[:current_member]&.paid?

    # Per-collection override
    return @config[:show_paid] == "true" if @config.key?(:show_paid)

    # Global default from members.yml (shows to everyone with lock icon)
    SiteConfig.feature("members", "everyone.show_paid_content") || false
  end
end

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
    return unless SiteConfig.feature_enabled?('members')
    return if should_show_paid?

    # Return early if items is an array (empty collection or already filtered)
    return @items if @items.is_a?(Array)

    # Hide paid posts
    @items = @items.where("json_extract(metadata, '$.audience') IS NULL OR json_extract(metadata, '$.audience') != ?", 'paid')
  end

  def should_show_paid?
    # Per-collection override
    return @config[:show_paid] == 'true' if @config.key?(:show_paid)

    # Global default from members.yml
    SiteConfig.feature('members', 'everyone.show_paid_content') || false
  end
end

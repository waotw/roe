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
    return unless members_enabled?
    return if should_show_paid?

    # Hide paid posts
    @items = @items.where("json_extract(metadata, '$.audience') IS NULL OR json_extract(metadata, '$.audience') != ?", 'paid')
  end

  def should_show_paid?
    # Per-collection override
    return @config[:show_paid] == 'true' if @config.key?(:show_paid)

    # Global default from members.yml
<<<<<<< Updated upstream
    SiteConfig.default('members', 'non-members')&.dig('show_paid_content') || false
=======
    SiteConfig.feature('members', 'everyone.show_paid_content') || false
>>>>>>> Stashed changes
  end
end

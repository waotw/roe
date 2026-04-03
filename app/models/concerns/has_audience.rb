module HasAudience
  extend ActiveSupport::Concern

  AUDIENCES = %w[everyone paid].freeze

  included do
    # Validation for metadata-based audience
    validate :audience_must_be_valid

    # Scopes
    scope :public_content, -> {
      where("json_extract(metadata, '$.audience') IS NULL OR json_extract(metadata, '$.audience') = 'everyone'")
    }
    scope :premium_content, -> {
      where("json_extract(metadata, '$.audience') = 'paid'")
    }
    scope :accessible_to, ->(member) {
      if member&.paid? && member&.active?
        all  # Paid members see everything
      else
        public_content  # Free/nil members see only public
      end
    }
  end

  # Read audience from metadata
  def audience
    metadata['audience'] || 'everyone'
  end

  # Write audience to metadata
  def audience=(value)
    metadata['audience'] = value
  end

  def publicly_accessible?
    audience == 'everyone'
  end

  def premium?
    audience == 'paid'
  end

  def accessible_to?(member)
    return true if publicly_accessible?
    return false if member.nil?
    member.can_access?(self)
  end

  def newsletter_audience
    premium? ? 'paid' : 'everyone'
  end

  private

  def audience_must_be_valid
    return if audience.in?(AUDIENCES)
    errors.add(:audience, "must be one of: #{AUDIENCES.join(', ')}")
  end
end

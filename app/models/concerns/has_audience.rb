module HasAudience
  extend ActiveSupport::Concern

  AUDIENCES = %w[everyone paid only_paid].freeze

  included do
    # NOTE: no audience validation. Roe is file-first — the user can edit
    # YAML directly with anything, and the publish modal gates audience
    # to a known value before content actually goes live. A model-level
    # validation here would silently block ContentSync/ContentWatcher
    # from updating the DB when a file is saved with an empty or unknown
    # audience, which makes the admin UI lie about what's on disk.

    # Scopes — treat NULL and empty string the same as 'everyone' so a
    # blank audience field doesn't accidentally hide a post from the
    # public listings.
    scope :public_content, -> {
      where(<<~SQL.squish)
        json_extract(metadata, '$.audience') IS NULL
          OR json_extract(metadata, '$.audience') = ''
          OR json_extract(metadata, '$.audience') = 'everyone'
      SQL
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

  # Read audience from metadata. Empty / nil reads as 'everyone' so the
  # rest of the app treats blank-audience posts as publicly accessible
  # (matching the default behavior when the field is omitted entirely).
  def audience
    value = metadata['audience'].to_s.strip
    value.empty? ? 'everyone' : value
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
end

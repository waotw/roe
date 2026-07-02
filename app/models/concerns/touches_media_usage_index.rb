# frozen_string_literal: true

# Drops the cached MediaUsageIndex whenever a content record that could
# reference media is created, updated, or destroyed — so the media browse
# page's "Used in" backlinks stay accurate. after_commit so we only bust
# the cache once the change is actually persisted.
module TouchesMediaUsageIndex
  extend ActiveSupport::Concern

  included do
    after_commit :invalidate_media_usage_index
  end

  private

  def invalidate_media_usage_index
    MediaUsageIndex.invalidate!
  end
end

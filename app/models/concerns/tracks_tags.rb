# Keeps the tags: list in content.yml following this record's tags. Every
# save path ends in a record save — the admin editor, the file watcher, a full
# sync, the tag manager itself — so this is the one place the list is updated.
#
# after_commit, so a check for "is this tag still used anywhere" sees the
# database as it now is.
module TracksTags
  extend ActiveSupport::Concern

  included do
    after_commit :update_tag_list, on: %i[create update]
    after_commit :release_tags, on: :destroy
  end

  private

  def update_tag_list
    return unless TagList.tracked?(self)

    if previously_new_record?
      before = []
    else
      change = saved_changes["metadata"]
      return unless change

      before = tags_from(change.first)
    end
    after = TagList.clean(tags)
    TagList.record_change(added: after - before, removed: before - after) unless before == after
  rescue => e
    Rails.logger.error("[TracksTags] #{self.class.name} #{id}: #{e.message}")
  end

  def release_tags
    return unless TagList.tracked?(self)

    TagList.record_change(added: [], removed: TagList.clean(tags))
  rescue => e
    Rails.logger.error("[TracksTags] #{self.class.name} #{id}: #{e.message}")
  end

  def tags_from(metadata)
    metadata = JSON.parse(metadata) if metadata.is_a?(String)
    value = metadata.is_a?(Hash) ? metadata["tags"] : nil
    case value
    when Array then TagList.clean(value)
    when String then TagList.clean(value.split(","))
    else []
    end
  rescue JSON::ParserError
    []
  end
end

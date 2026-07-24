# Bulk delete / publish for the posts, pages, and products index tables.
# Selection happens client-side (bulk_select_controller.js); these endpoints
# receive the chosen ids and act.
#
# Host controllers must define:
#   bulk_model       → the AR class (Post / Page / Product)
#   bulk_index_path  → where to redirect back to
#   bulk_label       → singular noun ("post" / "page" / "product")
# and may override:
#   prepare_publish_metadata(record, metadata) → tweak frontmatter before write
#     (posts use it to freeze the podcast GUID)
#   bulk_publish_side_effect(record) → run post-publish effects, return true
#     when it queued something worth counting (posts use it for newsletters)
module BulkContentActions
  extend ActiveSupport::Concern

  # Delete whatever's selected — draft or published — file and record.
  def bulk_destroy
    count = 0
    bulk_model.where(id: bulk_ids).find_each do |record|
      delete_content_file(record)
      record.destroy
      count += 1
    end
    redirect_back fallback_location: bulk_index_path,
                  notice: "Deleted #{helpers.pluralize(count, bulk_label)}."
  end

  # Publish the selected DRAFTS that have no warnings. Already-published or
  # attention-needing items are skipped (the UI also hides the button when any
  # selected draft needs attention, but we re-check server-side).
  def bulk_publish
    published = 0
    side_effects = 0
    skipped = 0

    bulk_model.where(id: bulk_ids).find_each do |record|
      if publishable_draft?(record)
        publish_content!(record)
        side_effects += 1 if bulk_publish_side_effect(record)
        published += 1
      else
        skipped += 1
      end
    end

    notice = "Published #{helpers.pluralize(published, bulk_label)}."
    notice += " #{helpers.pluralize(side_effects, 'newsletter')} queued." if side_effects.positive?
    notice += " Skipped #{skipped} (already live or needs attention)." if skipped.positive?
    redirect_back fallback_location: bulk_index_path, notice: notice
  end

  private

  # Overridable hooks (defaults are no-ops).
  def prepare_publish_metadata(_record, metadata) = metadata
  def bulk_publish_side_effect(_record) = false

  def bulk_ids
    Array(params[:ids]).flatten.map(&:to_s).select { |s| s.match?(/\A\d+\z/) }
  end

  def publishable_draft?(record)
    !record.published? && !record.publish_warnings?
  end

  # Flip status → published in the file and sync. Model-agnostic: posts, pages,
  # and products all serialize frontmatter through HasMetadata.
  def publish_content!(record)
    path = content_path(record)
    content = File.read(path)
    return unless content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)/m

    metadata = YAML.safe_load($1, permitted_classes: [ Date, Time, Symbol ]) || {}
    body = $2
    metadata["status"] = "published"
    metadata = prepare_publish_metadata(record, metadata)

    File.write(path, "---\n#{record.class.format_metadata_yaml(metadata)}\n---\n#{body}".gsub(/\r\n/, "\n"))
    ContentSync.sync_file(path)
    record.reload
  end

  def delete_content_file(record)
    path = content_path(record)
    site_root = File.expand_path(RoeSitePaths::SITE_PATH)
    FileUtils.rm_f(path) if File.expand_path(path).start_with?(site_root + File::SEPARATOR) && File.exist?(path)
  end

  # Posts/pages store an absolute file_path; products store one relative to the
  # site root.
  def content_path(record)
    path = record.file_path.to_s
    path.start_with?("/") ? path : File.join(RoeSitePaths::SITE_PATH, path)
  end
end

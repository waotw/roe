class Import < ApplicationRecord
  # Status tracking for the overall import process
  enum :status, {
    pending: 0,
    uploading: 1,
    extracting: 2,
    importing_posts: 3,
    importing_media: 4,
    importing_members: 5,
    importing_deliveries: 6,
    completed: 7,
    failed: 8,
    rolled_back: 9
  }, prefix: true

  # Phase tracking for the wizard (1-4)
  # Phase 1: Upload & Configure
  # Phase 2: Posts & Media
  # Phase 3: Members
  # Phase 4: Deliveries

  has_many :posts, dependent: :nullify
  has_many :media, class_name: "Medium", dependent: :nullify
  # Members use :restrict_with_error so a direct destroy can't silently nil
  # out import_id on imported members — that would defeat the resend filter
  # in PostsController. To remove an import that created members, use the
  # explicit `MembersImporter#rollback` action which destroys members first.
  has_many :members, dependent: :restrict_with_error

  validates :source_type, presence: true
  validates :phase, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 4 }

  # Configuration helpers
  def base_url
    configuration["base_url"]
  end

  def base_url=(url)
    configuration["base_url"] = url
  end

  def filters
    configuration["filters"] || {}
  end

  def options
    configuration["options"] || {}
  end

  # Stats helpers
  def increment_stat(key, amount = 1)
    current = stats[key.to_s] || 0
    stats[key.to_s] = current + amount
    save!
  end

  def set_stat(key, value)
    stats[key.to_s] = value
    save!
  end

  # ── File / Feed importers: content tagged by import_ref in its metadata ─────
  # These importers write file-backed posts/pages and tag each with
  # `import_ref: <this import's id>` in frontmatter (rather than the Substack FK
  # `posts` association above), so the same mechanism covers pages too. These
  # helpers let an import list and roll back exactly what it created.
  def ref_content(model)
    model.where("json_extract(metadata, '$.import_ref') = ?", id)
  end

  def ref_draft_count
    [ Post, Page ].sum { |m| ref_content(m).where("json_extract(metadata, '$.status') = ?", "draft").count }
  end

  # Non-draft (published/unlisted) content this import created — kept on delete.
  def ref_published_count
    [ Post, Page ].sum { |m| ref_content(m).where("json_extract(metadata, '$.status') <> ?", "draft").count }
  end

  # Delete this import's DRAFT posts/pages — file and record — leaving published
  # ones for manual removal. Returns the count deleted.
  def delete_draft_content!
    site_root = File.expand_path(RoeSitePaths::SITE_PATH)
    deleted = 0
    [ Post, Page ].each do |model|
      ref_content(model).where("json_extract(metadata, '$.status') = ?", "draft").find_each do |rec|
        path = rec.file_path
        if path.present? && File.expand_path(path).start_with?(site_root + File::SEPARATOR) && File.exist?(path)
          FileUtils.rm_f(path)
        end
        rec.destroy
        deleted += 1
      end
    end
    deleted
  end

  # Phase management
  def complete_phase!(phase_number)
    return if completed_phases.include?(phase_number)

    completed_phases << phase_number
    save!
  end

  def phase_completed?(phase_number)
    completed_phases.include?(phase_number)
  end

  # Derive current phase from status and completed phases
  def current_phase
    return 4 if status_completed? || status_importing_deliveries?
    return 3 if status_importing_members? || phase_completed?(2)
    return 2 if status_importing_posts? || status_importing_media? || phase_completed?(1)
    1 # Default to phase 1 (upload/configure)
  end

  # Rollback support
  def can_rollback?
    !status_rolled_back? && (status_importing_posts? || status_importing_media? ||
                            status_importing_members? || status_importing_deliveries? ||
                            status_completed?)
  end

  def mark_failed!(message)
    update!(
      status: :failed,
      error_message: message,
      completed_at: Time.current
    )
  end

  def mark_completed!
    update!(
      status: :completed,
      completed_at: Time.current
    )
  end

  # Archive file path helper
  def archive_path
    return nil unless archive_file.present?

    File.join(Rails.root, "tmp", "imports", archive_file)
  end

  # Extract path helper
  def extract_path
    return nil unless id.present?

    File.join(Rails.root, "tmp", "imports", "extract_#{id}")
  end

  # Cleanup temporary files
  def cleanup_temp_files!
    return unless extract_path.present? && File.directory?(extract_path)

    FileUtils.rm_rf(extract_path)
  end

  # Build a substack_post_id → rss_item lookup hash for fast per-episode
  # access during import. Returns nil when no RSS data was captured.
  def rss_items_by_post_id
    return nil unless rss_data.is_a?(Hash)
    items = rss_data["items"] || rss_data[:items] || []
    items.each_with_object({}) do |item, h|
      pid = item["substack_post_id"] || item[:substack_post_id]
      h[pid.to_s] = item if pid.present?
    end
  end

  # Clear the rss_data column once an import is done with it. The parsed
  # data contains token-bearing enclosure URLs (paid Substack feeds) that
  # we don't want lingering in the DB after the import completes.
  def scrub_rss_data!
    update_column(:rss_data, nil) if rss_data.present?
  end
end

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
  has_many :members, dependent: :nullify

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

  # Phase management
  def complete_phase!(phase_number)
    return if completed_phases.include?(phase_number)

    completed_phases << phase_number
    save!
  end

  def phase_completed?(phase_number)
    completed_phases.include?(phase_number)
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
end

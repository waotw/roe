# frozen_string_literal: true

# Rewrites every on-disk reference to a media path when a media file is
# renamed, so links don't break. Covers content files (posts, pages,
# documentation, products) and config YAML — the same sources
# MediaUsageIndex scans. The file is the source of truth, so we edit the
# file and re-sync the DB record from it. Returns the number of files changed.
class MediaReferenceRewriter
  CONTENT_MODELS = %w[Post Page Documentation Product].freeze

  def self.rewrite(old_path, new_path)
    new(old_path, new_path).rewrite
  end

  def initialize(old_path, new_path)
    @old_path = old_path.to_s
    @new_path = new_path.to_s
  end

  # => count of files rewritten
  def rewrite
    return 0 if @old_path.empty? || @old_path == @new_path

    rewrite_content + rewrite_configs
  end

  private

  def rewrite_content
    count = 0
    CONTENT_MODELS.each do |name|
      model = name.constantize
      model.find_each do |record|
        file = absolute_file_path(record.file_path)
        next unless file && File.file?(file)

        next unless replace_in_file(file)
        # Re-read the file into the DB so the admin UI reflects the change
        # immediately (the watcher would eventually, but this is instant).
        model.create_or_update_from_file(file) if model.respond_to?(:create_or_update_from_file)
        count += 1
      end
    end
    count
  end

  # Resolve a record's stored file_path to an absolute on-disk path. Post,
  # Page and Documentation store absolute paths; Product stores one relative
  # to SITE_PATH — without this, File.file? was false for products and every
  # product reference was silently skipped.
  def absolute_file_path(file_path)
    fp = file_path.to_s
    return nil if fp.empty?

    fp.start_with?("/") ? fp : File.join(RoeSitePaths::SITE_PATH, fp)
  end

  def rewrite_configs
    count = 0
    MediaUsageIndex::CONFIG_SOURCES.each do |source|
      file = source[:file].call
      next unless file && File.file?(file)

      count += 1 if replace_in_file(file)
    end
    SiteConfig.reload! if count.positive?
    count
  end

  # Literal, whole-path replace. The media path is a specific, unique string
  # (e.g. "/media/images/logo.svg" or a spaced filename), so a plain gsub is
  # safe and handles both frontmatter and body references. Returns true if
  # the file changed.
  def replace_in_file(file)
    text = File.read(file)
    return false unless text.include?(@old_path)

    File.write(file, text.gsub(@old_path, @new_path))
    true
  end
end

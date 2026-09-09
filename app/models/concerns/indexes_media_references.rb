# frozen_string_literal: true

# Keeps media_references current for a content record, and keeps each
# referenced Medium's cached audience in step.
#
# This used to live on Post alone, which meant a file used only by a page or a
# product looked unreferenced. That was cosmetic while the index only drove the
# media browser's "Used in" column; it stopped being cosmetic when the index
# started deciding whether a file is served to the public.
module IndexesMediaReferences
  extend ActiveSupport::Concern

  # Metadata keys whose value may be a /media/ path. Body markdown is scanned
  # separately — see extract_media_paths.
  MEDIA_METADATA_FIELDS = %w[image audio video thumbnail cover poster].freeze

  included do
    # prepend so this runs before the association's own dependent: :destroy
    # callback. Without it the reference rows are already gone by the time we
    # look, and destroying the last free reference wouldn't re-protect the file
    # (or destroying the last paid one wouldn't release it).
    before_destroy :remember_referenced_media, prepend: true

    has_many :media_references, as: :referenceable, dependent: :destroy
    has_many :media, through: :media_references, source: :medium

    after_save :update_media_references
    after_destroy :recompute_media_audience
  end

  # Every /media/ path this record points at, from its body and its metadata.
  def extract_media_paths
    paths = []

    if respond_to?(:content) && content.present?
      paths += content.scan(/!\[.*?\]\((\/media\/[^\)]+)\)/).flatten
      paths += content.scan(/<img[^>]+src=["'](\/media\/[^"']+)["']/).flatten
      paths += content.scan(/<(?:audio|video)[^>]+src=["'](\/media\/[^"']+)["']/).flatten
    end

    if metadata.present?
      MEDIA_METADATA_FIELDS.each do |field|
        value = metadata[field]
        paths << value if value.is_a?(String) && value.start_with?("/media/")
      end
    end

    paths.uniq
  end

  # Whether this record's media should be protected. Overridden by anything
  # without an audience — a product is always free for now.
  def media_audience
    metadata["audience"].to_s.strip == "paid" ? "paid" : "free"
  end

  private

  def update_media_references
    previous = media_references.pluck(:medium_id)
    referenced = Medium.where(file_path: extract_media_paths)

    media_references.destroy_all
    referenced.each { |medium| media_references.create(medium: medium) }

    Medium.recompute_audience!(previous | referenced.map(&:id))
  end

  def remember_referenced_media
    @referenced_medium_ids = media_references.pluck(:medium_id)
    true
  end

  def recompute_media_audience
    Medium.recompute_audience!(@referenced_medium_ids)
  end
end

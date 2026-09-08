class Medium < ApplicationRecord
  has_many :media_references, dependent: :destroy
  # `source: :referenceable` with a type is how a polymorphic through-association
  # narrows to one class. Kept because the media browser lists posts by name;
  # pages and products get the same treatment.
  has_many :posts, through: :media_references, source: :referenceable, source_type: "Post"
  has_many :pages, through: :media_references, source: :referenceable, source_type: "Page"
  has_many :products, through: :media_references, source: :referenceable, source_type: "Product"
  belongs_to :import, optional: true

  before_save :normalize_media_type
  before_destroy :delete_variants, if: :image?
  # Production included: both deploy targets run Solid Queue inside Puma
  # (SOLID_QUEUE_IN_PUMA in the generated fly.toml and config/deploy.yml), so
  # the job actually runs there. Skipping it meant the first visitor to every
  # image was served the full-size original while the on-demand path caught up.
  after_create :queue_variant_generation, if: :image?

  # Scope helpers for filtering
  scope :images, -> { where(media_type: "images") }
  scope :audio, -> { where(media_type: "audio") }
  scope :video, -> { where(media_type: "video") }
  scope :fonts, -> { where(media_type: "fonts") }
  scope :unused, -> {
      left_joins(:media_references)
        .where(media_references: { id: nil })
    }
  # Add this scope
  scope :originals_only, -> { where.not("file_path LIKE ?", "%/variants/%") }

  # Whether this file may be served to anyone, cached so the check on every
  # image request is one indexed column read rather than a join across posts
  # and pages.
  scope :paid, -> { where(audience: "paid") }
  scope :free, -> { where(audience: "free") }

  def paid?
    audience == "paid"
  end

  # Whether a requested /media/ path may only be served to someone entitled to
  # it. Handles variants, which have no Medium row of their own.
  #
  # A variant is a resized copy of its source living at
  # <dir>/variants/<base>-<size><ext>, and the extension may differ (WebP
  # siblings are generated for every native variant). So a paid image's
  # variants were being served to anyone — the lookup missed, because nothing
  # in the database has that path.
  def self.protected_path?(web_path)
    paid.exists?(file_path: source_paths_for(web_path))
  end

  # The path itself, or — for a variant — every path its source could have.
  # Built as an exact list rather than a LIKE, because filenames routinely
  # contain underscores and `_` is a single-character wildcard in SQL.
  def self.source_paths_for(web_path)
    path = web_path.to_s
    segments = path.split("/")
    return [ path ] unless segments.include?("variants")

    filename = segments.pop
    segments.delete_at(segments.rindex("variants"))
    dir = segments.join("/")

    base = File.basename(filename, ".*")
    sizes = ImageVariantGenerator::VARIANTS.keys.map(&:to_s)
    source_base = base.sub(/-(#{Regexp.union(sizes)})\z/, "")

    # A file sitting in a variants directory that doesn't end in a known size
    # isn't one of ours — judge it on its own path rather than guessing.
    return [ path ] if source_base == base

    ImageVariantGenerator::IMAGE_EXTENSIONS.map { |ext| "#{dir}/#{source_base}#{ext}" }
  end

  # Files referenced by BOTH paid and free content. These resolve to free —
  # public wins — so they're the ones to check when something you meant to
  # protect is readable: the file is also used somewhere public.
  def self.mixed_audience_ids
    paid_ids = MediaReference
      .joins("INNER JOIN posts ON posts.id = media_references.referenceable_id AND media_references.referenceable_type = 'Post'")
      .where("json_extract(posts.metadata, '$.audience') = ?", "paid")
      .distinct.pluck(:medium_id)

    paid_ids |= MediaReference
      .joins("INNER JOIN pages ON pages.id = media_references.referenceable_id AND media_references.referenceable_type = 'Page'")
      .where("json_extract(pages.metadata, '$.audience') = ?", "paid")
      .distinct.pluck(:medium_id)

    return [] if paid_ids.empty?

    # Of those, the ones that ended up free — i.e. something public uses them too.
    where(id: paid_ids, audience: "free").pluck(:id)
  end

  # Which post type's media a config file's audience affects. A show or a
  # release carries an audience its episodes and tracks inherit, so changing
  # one has to re-resolve their files — nothing else would, since no post is
  # saved when you edit podcast.yml.
  AUDIENCE_BEARING_CONFIGS = {
    "features/podcast" => "podcast",
    "features/music"   => "music"
  }.freeze

  # Re-resolve every file referenced by posts of the type this config governs.
  # No-op for any other config.
  def self.recompute_for_config(config_type)
    post_type = AUDIENCE_BEARING_CONFIGS[config_type.to_s] or return

    ids = MediaReference
      .joins("INNER JOIN posts ON posts.id = media_references.referenceable_id AND media_references.referenceable_type = 'Post'")
      .where("json_extract(posts.metadata, '$.post_type') = ?", post_type)
      .distinct.pluck(:medium_id)

    recompute_audience!(ids)
  end

  # Re-resolve every file currently marked paid.
  #
  # audience is a cached column, so a change to what counts as protected leaves
  # existing rows saying the old thing. Only paid rows can be stale: every rule
  # here moves files toward public — a featured image, anything above a paywall
  # — and nothing that resolved free could later become paid. So this visits the
  # small set rather than the whole library, which is what makes it cheap enough
  # to run on boot instead of asking someone to run a task.
  #
  # Idempotent: a row that resolves to what it already holds isn't written.
  def self.recompute_paid!
    recompute_audience!(paid.pluck(:id))
  end

  # Recalculate the cached audience for the given media.
  #
  # A file is protected only when it has references and every one of them is
  # paid. Public wins deliberately: a file used by both a paid post and a free
  # page stays public, because the alternative is that editing an unrelated
  # paid post silently breaks an image on a page anyone can read. An
  # unreferenced file is free — nothing is gating it.
  def self.recompute_audience!(ids)
    ids = Array(ids).compact.uniq
    return if ids.empty?

    where(id: ids).includes(media_references: :referenceable).find_each do |medium|
      audiences = medium.media_references.filter_map do |ref|
        record = ref.referenceable
        next unless record

        # Ask about THIS file, not the record as a whole. A paid post's featured
        # image and anything above its paywall are public — see
        # ResolvesMediaAudience. Records without the concern (products,
        # documentation) answer for themselves as before.
        if record.respond_to?(:media_audience_for)
          record.media_audience_for(medium.file_path)
        else
          record.media_audience
        end
      end

      resolved = audiences.any? && audiences.all?("paid") ? "paid" : "free"
      medium.update_column(:audience, resolved) unless medium.audience == resolved
    end
  end

  # Variant status scopes — back the indexed `variants_status` column.
  # Stamped by ImageVariantGenerator.mark_complete_for after a successful
  # generation run; row stays at the "pending" default until then. The
  # pending scope treats NULL the same as "pending" since older rows
  # predate the column default.
  scope :with_complete_variants, -> { where(variants_status: "complete") }
  scope :with_pending_variants, -> { where("variants_status IS NULL OR variants_status != ?", "complete") }

  def image?
    media_type == "images"
  end

  def variants_ready?
    return false unless image?
    # Fast path: trust the column when it says complete. mark_complete_for
    # only stamps "complete" after a post-loop variants_exist? check, so
    # a true here is a real "all on-disk variants present" signal.
    return true if variants_status == "complete"

    # Slow path / self-heal: column might not have been backfilled yet
    # (rows that predate the wired-up status). Confirm against the
    # filesystem and stamp the column on the way out so subsequent calls
    # take the fast path.
    source_path = File.join(RoeSitePaths::SITE_PATH, file_path.sub(%r{^/}, "")).to_s
    return false unless ImageVariantGenerator.variants_exist?(source_path)

    update_columns(variants_status: "complete", variants_generated_at: Time.current) if persisted?
    true
  end


  def variant_path(variant_name)
    return nil unless image?
    ImageVariantGenerator.variant_path_for(file_path, variant_name)
  end

  def variant_stats
    ImageVariantGenerator.stats_for(self)
  end

  def queue_variant_generation
    return unless image?

    # Proactively build only the cheap baseline preview; the rest of the
    # ladder is generated on-demand when the image is actually rendered.
    ImageVariantGenerator.queue_baseline!(file_path)
  end

  # True once the upload-time baseline (ImageVariantGenerator
  # .baseline_variant_names — small + largest non-upscaled size) is on disk.
  # The admin grid serves that preview and gates on this rather than the
  # full ladder, so an image that's only ever a baseline (never rendered
  # on the site) still shows a proper thumbnail instead of the original.
  def baseline_ready?
    return false unless image?
    # Fast path: a "complete" full ladder trivially includes the baseline,
    # so trust the column and skip the filesystem stat on the common case.
    return true if variants_status == "complete"

    ImageVariantGenerator.baseline_exists?(
      File.join(RoeSitePaths::SITE_PATH, file_path.sub(%r{^/}, "")).to_s
    )
  end

  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end

  private

  def delete_variants
    return unless image?

    source_path = File.join(RoeSitePaths::SITE_PATH, file_path.sub(%r{^/}, ""))
    variants_dir = File.join(File.dirname(source_path), "variants")

    return unless Dir.exist?(variants_dir)

    # Delegate variant-path construction to ImageVariantGenerator so
    # naming stays in one place — this matters for HEIC/HEIF sources
    # where variants are emitted as .jpg, not .heic.
    ImageVariantGenerator::VARIANTS.keys.each do |variant_name|
      variant_file = ImageVariantGenerator.variant_path_for(source_path, variant_name)

      if File.exist?(variant_file)
        File.delete(variant_file)
        Rails.logger.info "[Medium] Deleted variant: #{variant_file}"
      end

      # Also check for .webp variant if it exists
      webp_file = variant_file.sub(File.extname(variant_file), ".webp")
      if File.exist?(webp_file)
        File.delete(webp_file)
        Rails.logger.info "[Medium] Deleted webp variant: #{webp_file}"
      end
    end
  rescue => e
    Rails.logger.error "[Medium] Failed to delete variants: #{e.message}"
  end

  def normalize_media_type
    # If media_type is blank, extract from file_path
    if media_type.blank? && file_path.present?
      self.media_type = File.extname(file_path).delete_prefix(".").downcase
    end

    extension = media_type&.downcase

    case extension
    when "png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "heic", "heif"
      self.media_type = "images"
    when "woff", "woff2", "ttf", "otf"
      self.media_type = "fonts"
    when "mp3", "m4a", "wav", "ogg", "flac", "aac"
      self.media_type = "audio"
    when "mp4", "webm", "ogv", "mov", "avi", "mkv"
      self.media_type = "video"
    end
  end
end

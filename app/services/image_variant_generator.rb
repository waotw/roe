# frozen_string_literal: true

class ImageVariantGenerator
  VARIANTS = {
    thumb:  { resize_to_fill:  [ 150, 150 ] },     # admin grid, square OG
    small:  { resize_to_limit: [ 400, 400 ] },     # cards, sidebars
    medium: { resize_to_limit: [ 800, 800 ] },     # body content default
    large:  { resize_to_limit: [ 1200, 1200 ] },   # full-width content
    xl:     { resize_to_limit: [ 1800, 1800 ] }    # hero / full-bleed / OG image
  }.freeze

  WEBP_QUALITY = 85  # Quality for WebP conversion
  # Generate `.webp` siblings alongside each native-format variant. The
  # ResponsiveImageRenderer emits a `<source type="image/webp">` first
  # in the picture tag so capable browsers (universal modern support)
  # pick the smaller WebP file; older browsers fall through to the
  # native-format source.
  GENERATE_WEBP = true

  # Source extensions we'll generate variants for. HEIC/HEIF are included
  # so they're treated consistently with Medium#image? — variant_path_for
  # remaps their variants to .jpg below since browsers can't display HEIC.
  # (The original HEIC file remains; the substack importer converts at
  # download time, but manual uploads land as-is. Source-side conversion
  # for non-import flows is a follow-up.)
  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .heic .heif].freeze
  HEIC_EXTENSIONS = %w[.heic .heif].freeze

  # How long the "this path is queued" Rails.cache flag lives if the job
  # never gets to its ensure block to clear it (crash, OOM, worker kill).
  # Long enough to actually deduplicate a busy render burst, short enough
  # that a stuck flag self-recovers.
  QUEUE_DEDUP_TTL = 1.hour

  class << self
    def process_mode
      # In production: on-demand only (lazy)
      # In development: eager (generate immediately)
      if Rails.env.production?
        :on_demand
      else
        :eager
      end
    end

    def available?
      @available ||= begin
        # Try to require ruby-vips (won't fail if gem is installed but lib is missing)
        require "ruby-vips"

        # Test that libvips library is actually accessible
        Vips.version_string
        true
      rescue LoadError => e
        Rails.logger.info "[ImageVariants] ruby-vips gem not available: #{e.message}"
        false
      rescue NameError => e
        Rails.logger.info "[ImageVariants] libvips library not found: #{e.message}"
        false
      rescue => e
        Rails.logger.info "[ImageVariants] Image processing unavailable: #{e.message}"
        false
      end
    end

    def generate_variants(source_path, medium_id: nil)
      return false unless available?
      return false unless image_file?(source_path)

      source_path = normalize_path(source_path)
      return false unless File.exist?(source_path)

      # Hard boundary: a variant must never be the source of more
      # variants. variant_path_for derives the output dir from
      # File.dirname(source_path), so a variant input produces a nested
      # variants/variants/ directory and the count compounds every run.
      # Callers (ContentSync, ContentWatcher, the rake tasks) already
      # filter, but enforcing it here too removes the foot-gun for any
      # future caller, including ad-hoc console invocations.
      if variant_path?(source_path)
        Rails.logger.warn "[ImageVariants] Refusing to generate variants for a variant file: #{source_path}"
        return false
      end

      Rails.logger.info "[ImageVariants] Processing #{source_path}"

      # Ensure variants directory exists
      variants_dir = File.join(File.dirname(source_path), "variants")
      FileUtils.mkdir_p(variants_dir)

      # Sequential. Per-variant mtime check inside generate_variant skips
      # work when a variant is already up-to-date relative to the source,
      # so we don't need an outer "everything fresh?" short-circuit —
      # always running mark_complete_for at the end self-heals the DB
      # status column for files whose variants exist but were never
      # stamped (older imports, manual file drops).
      VARIANTS.each do |name, operations|
        generate_variant(source_path, name, operations)
      end

      # Only stamp the row "complete" if every native variant (and WebP
      # sibling, when GENERATE_WEBP is on) actually exists on disk. The
      # per-variant rescue inside generate_variant swallows individual
      # failures so the loop keeps going — without this verify step we'd
      # falsely mark partially-generated images as complete and the next
      # backfill_status sweep would have to silently undo the lie.
      if variants_exist?(source_path)
        Rails.logger.info "[ImageVariants] ✓ Complete: #{File.basename(source_path)}"
        mark_complete_for(source_path)
        true
      else
        Rails.logger.warn "[ImageVariants] ⚠ Partial: some variants missing for #{File.basename(source_path)} — leaving status pending"
        false
      end
    rescue => e
      Rails.logger.error "[ImageVariants] Failed #{source_path}: #{e.message}"
      false
    end

    def variant_exists?(source_path, variant_name)
      path = variant_path_for(source_path, variant_name)
      File.exist?(path)
    end

    def webp_variant_exists?(source_path, variant_name)
      path = variant_path_for(source_path, variant_name)
      webp_path = path.sub(File.extname(path), ".webp")
      File.exist?(webp_path)
    end

    def variant_path_for(source_path, variant_name)
      source_path = normalize_path(source_path)
      dir = File.dirname(source_path)
      base = File.basename(source_path, ".*")
      ext = File.extname(source_path)
      # HEIC/HEIF aren't browser-displayable; emit JPG variants so the
      # picture/srcset pipeline produces something the browser can render.
      ext = ".jpg" if HEIC_EXTENSIONS.include?(ext.downcase)
      File.join(dir, "variants", "#{base}-#{variant_name}#{ext}")
    end

    # Idempotent enqueue: skips if a job for this web path was queued
    # within the dedup window. The cache flag is cleared by the job's
    # ensure block (see #dequeue) so subsequent retries can re-queue
    # naturally; the TTL is a safety net for jobs that crash before
    # reaching the ensure. Returns true if a job was enqueued, false if
    # deduped.
    #
    # Pass `force: true` to bypass the dedup check — used by user-
    # initiated rake/admin actions where "queue this now" must not be
    # silently swallowed by a stale cache flag from a prior crashed run.
    def queue!(web_path, force: false)
      return false unless available?
      # Same boundary as #generate_variants: never queue a variant path.
      # The job would happily process it and produce variants/variants/.
      if variant_path?(web_path)
        Rails.logger.warn "[ImageVariants] Refusing to queue a variant file: #{web_path}"
        return false
      end
      cache_key = queue_cache_key(web_path)
      return false if !force && Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, true, expires_in: QUEUE_DEDUP_TTL)
      GenerateImageVariantsJob.perform_later(web_path, nil)
      true
    end

    # Cleared by the job (success or failure) so the next renderer hit
    # for a still-missing variant can re-queue without waiting for the
    # TTL to expire.
    def dequeue(web_path)
      Rails.cache.delete(queue_cache_key(web_path))
    end

    def queue_cache_key(web_path)
      "variants_queued:#{web_path}"
    end

    def queue_missing_variants
      return 0 unless available?

      image_paths = Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media/images/**/*.{jpg,jpeg,png,gif,webp,heic,heif}"))
                       .reject { |p| p.include?("/variants/") }

      queued_count = 0
      image_paths.each do |path|
        next if variants_exist?(path)

        relative_path = path.sub(RoeSitePaths::SITE_PATH.to_s, "")
        web_path = relative_path.start_with?("/") ? relative_path : "/#{relative_path}"

        # force: true so a stale "queued" cache flag from a previously
        # crashed/killed job run doesn't silently swallow this re-queue.
        # User-initiated batch operation — "queue everything missing"
        # has to actually queue everything missing.
        queued_count += 1 if queue!(web_path, force: true)
      end

      Rails.logger.info "[ImageVariants] Queued #{queued_count} images for variant generation"
      queued_count
    end

    def stats_for(medium)
      return nil unless medium&.image?

      source_path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, "")).to_s
      {
        total: VARIANTS.count,
        generated: VARIANTS.count { |name, _| variant_exists?(source_path, name) },
        missing: VARIANTS.keys.reject { |name| variant_exists?(source_path, name) },
        ready: variants_exist?(source_path)
      }
    end

    # "All variants present" = every native-format variant exists, AND
    # (when WebP is enabled) every WebP sibling exists too. This is the
    # gate the on-demand job and the renderer both consult, so flipping
    # GENERATE_WEBP on automatically routes every image through the
    # queue once until WebP siblings are filled in. After backfill, this
    # stays cheap (8 stat calls vs 4).
    def variants_exist?(source_path)
      source_path = normalize_path(source_path)
      VARIANTS.keys.all? do |name|
        variant_exists?(source_path, name) &&
          (!GENERATE_WEBP || webp_variant_exists?(source_path, name))
      end
    end

    def normalize_path(path)
      # Handle both web paths (/media/images/...) and absolute paths
      path = path.to_s

      # If already an absolute path to site directory, use it
      if path.start_with?(RoeSitePaths::SITE_PATH.to_s)
        path
      # If it's a web path starting with /media
      elsif path.start_with?("/media/")
        File.join(RoeSitePaths::SITE_PATH, path.sub(%r{^/}, "")).to_s
      # If it starts with Rails.root
      elsif path.start_with?(Rails.root.to_s)
        path
      # Otherwise assume it's relative
      else
        File.join(RoeSitePaths::SITE_PATH, path).to_s
      end
    end

    def image_file?(path)
      IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
    end

    # Detect any path inside a "variants" directory — file path or web
    # path, absolute or relative. Used by generate_variants and queue! to
    # refuse recursion. The check is segment-based so it doesn't false-
    # match a hypothetical file literally named e.g. "variantsX.jpg".
    def variant_path?(path)
      path.to_s.split("/").include?("variants")
    end

    private

    def generate_variant(source_path, variant_name, operations)
      variant_path = variant_path_for(source_path, variant_name)
      source_mtime = File.mtime(source_path)

      # Generate the native-format variant if missing or stale.
      unless File.exist?(variant_path) && File.mtime(variant_path) >= source_mtime
        require "image_processing/vips"
        pipeline = ImageProcessing::Vips.source(source_path)
        operations.each { |op, args| pipeline = pipeline.public_send(op, *args) }
        pipeline.call(destination: variant_path)
      end

      # Generate the WebP sibling if enabled, missing, or stale. Checked
      # independently so a re-run picks up missing WebPs without
      # regenerating the native variant — that's the on-disk backfill
      # path for installations that had GENERATE_WEBP off when their
      # variants were originally created.
      if GENERATE_WEBP
        webp_path = variant_path.sub(File.extname(variant_path), ".webp")
        unless File.exist?(webp_path) && File.mtime(webp_path) >= source_mtime
          require "image_processing/vips"
          pipeline = ImageProcessing::Vips.source(source_path)
          operations.each { |op, args| pipeline = pipeline.public_send(op, *args) }
          pipeline.convert("webp").saver(quality: WEBP_QUALITY).call(destination: webp_path)
        end
      end
    rescue => e
      Rails.logger.error "[ImageVariants] Failed to generate #{variant_name} for #{source_path}: #{e.message}"
    end

    # Stamp the matching Medium row as complete so `with_complete_variants`
    # / `with_pending_variants` scopes (and any future O(1) callers) can
    # avoid re-statting the filesystem. Looks up by web path derived from
    # the filesystem source. No-ops when no matching Medium exists yet
    # (e.g. variants generated for a file that ContentSync hasn't seen).
    def mark_complete_for(source_path)
      web_path = source_path.to_s.sub(RoeSitePaths::SITE_PATH.to_s, "")
      Medium.where(file_path: web_path).update_all(
        variants_status: "complete",
        variants_generated_at: Time.current
      )
    rescue => e
      Rails.logger.warn "[ImageVariants] Could not stamp variants_status for #{source_path}: #{e.class}: #{e.message}"
    end
  end
end

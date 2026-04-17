# frozen_string_literal: true

module SubstackImporter
  class DeliveriesImporter
    attr_reader :import, :stats, :errors

    def initialize(import)
      @import = import
      @stats = {
        deliveries_created: 0,
        deliveries_skipped_exists: 0,
        deliveries_skipped_no_member: 0,
        deliveries_skipped_no_post: 0,
        posts_with_deliveries: Set.new,
        members_who_received: Set.new,
        errors: []
      }
      @errors = []
    end

    def run
      @import.update!(status: :importing_deliveries, started_at: Time.current)

      # Ensure extract path exists (re-extract if needed)
      extract_path = ensure_extract_path
      return false unless extract_path

      # Find all delivery CSV files
      delivery_files = find_delivery_files(extract_path)
      Rails.logger.info "[SubstackImporter] Found #{delivery_files.count} delivery CSV files"

      if delivery_files.empty?
        @import.mark_failed!("No delivery CSV files found (*.delivers.csv)")
        return false
      end

      # Process each delivery file
      delivery_files.each do |file_path|
        process_delivery_file(file_path)
      end

      # Update stats
      @stats[:posts_with_deliveries] = @stats[:posts_with_deliveries].count
      @stats[:members_who_received] = @stats[:members_who_received].count

      @import.update!(
        status: :completed,
        stats: @import.stats.merge(@stats),
        completed_at: Time.current
      )

      # Complete phase 4
      @import.complete_phase!(4)

      true
    rescue => e
      Rails.logger.error "[SubstackImporter] Deliveries import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @import.mark_failed!(e.message)
      false
    end

    def rollback
      return false unless @import.can_rollback?

      Rails.logger.info "[SubstackImporter] Rolling back delivery import #{@import.id}"

      # Delete newsletter_sends created by this import
      deliveries_deleted = ::NewsletterSend.where(import: @import).count
      ::NewsletterSend.where(import: @import).destroy_all

      @import.update!(status: :rolled_back)

      Rails.logger.info "[SubstackImporter] Rollback complete: #{deliveries_deleted} deliveries removed"

      { deliveries_deleted: deliveries_deleted }
    end

    private

    def ensure_extract_path
      extract_path = @import.extract_path

      if extract_path.nil? || !Dir.exist?(extract_path)
        Rails.logger.info "[SubstackImporter] Extract path missing, re-extracting archive..."

        archive_path = @import.archive_path
        unless archive_path && File.exist?(archive_path)
          @errors << "Archive file not found"
          @import.mark_failed!("Cannot re-extract: archive file not found")
          return nil
        end

        begin
          extractor = SubstackImporter::Extractor.new(archive_path, extract_path: extract_path)
          extract_path = extractor.extract
          Rails.logger.info "[SubstackImporter] Re-extracted archive to: #{extract_path}"
        rescue => e
          @errors << "Re-extraction failed: #{e.message}"
          @import.mark_failed!("Failed to re-extract archive: #{e.message}")
          return nil
        end
      end

      extract_path
    end

    def find_delivery_files(extract_path)
      delivery_files = []

      # Look for delivery files at ROOT of extract directory (e.g., extract_18/135820468.delivers.csv)
      root_files = Dir.glob(File.join(extract_path, "*.delivers.csv"))
      delivery_files.concat(root_files)

      # Also look in posts/ subdirectory for backwards compatibility
      posts_dir = File.join(extract_path, "posts")
      if Dir.exist?(posts_dir)
        posts_files = Dir.glob(File.join(posts_dir, "**", "*.delivers.csv"))
        delivery_files.concat(posts_files)
      end

      delivery_files.uniq
    end

    def process_delivery_file(file_path)
      # Extract post_id from filename (e.g., "123456.delivers.csv" or "posts/123/123456.delivers.csv")
      basename = File.basename(file_path, ".delivers.csv")
      post_id = basename.split(".").first

      Rails.logger.info "[SubstackImporter] Processing deliveries for post: #{post_id}"

      # Find the post by substack_post_id
      post = find_post_by_substack_id(post_id)

      unless post
        Rails.logger.warn "[SubstackImporter] Post not found for substack_id: #{post_id}"
        @stats[:deliveries_skipped_no_post] += 1
        return
      end

      Rails.logger.info "[SubstackImporter] Found post: #{post.title} (ID: #{post.id})"

      # Parse CSV and create deliveries
      CSV.foreach(file_path, headers: true) do |row|
        process_delivery_row(row, post)
      end

      @stats[:posts_with_deliveries] << post.id
    rescue => e
      Rails.logger.error "[SubstackImporter] Failed to process delivery file #{file_path}: #{e.message}"
      @stats[:errors] << "#{File.basename(file_path)}: #{e.message}"
    end

    def find_post_by_substack_id(substack_id)
      ::Post.find_by("json_extract(metadata, '$.substack_post_id') = ?", substack_id)
    end

    def process_delivery_row(row, post)
      email = (row["email"] || row["Email"]).to_s.downcase.strip

      if email.blank?
        Rails.logger.debug "[SubstackImporter] Skipping blank email in delivery row"
        return
      end

      # Find member by email
      member = ::Member.find_by(email: email)

      unless member
        Rails.logger.debug "[SubstackImporter] Member not found for email: #{email}"
        @stats[:deliveries_skipped_no_member] += 1
        return
      end

      # Parse sent_at timestamp
      sent_at = parse_timestamp(row["sent_at"] || row["Sent At"] || row["timestamp"])

      unless sent_at
        Rails.logger.warn "[SubstackImporter] Could not parse timestamp for #{email}, using current time"
        sent_at = Time.current
      end

      # Check if delivery already exists (skip duplicates)
      if ::NewsletterSend.exists?(post: post, member: member)
        Rails.logger.debug "[SubstackImporter] Delivery already exists for #{email} on post #{post.id}"
        @stats[:deliveries_skipped_exists] += 1
        return
      end

      # Create the delivery record
      ::NewsletterSend.create!(
        post: post,
        member: member,
        sent_at: sent_at,
        import: @import
      )

      @stats[:deliveries_created] += 1
      @stats[:members_who_received] << member.id

      Rails.logger.debug "[SubstackImporter] Created delivery: #{email} -> #{post.title} at #{sent_at}"
    rescue => e
      Rails.logger.error "[SubstackImporter] Failed to create delivery for #{email}: #{e.message}"
      @stats[:errors] << "#{email}: #{e.message}"
    end

    def parse_timestamp(value)
      return nil if value.blank?

      # Try various timestamp formats
      formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S.%L",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d"
      ]

      formats.each do |format|
        begin
          return Time.strptime(value.to_s, format)
        rescue ArgumentError
          # Try next format
        end
      end

      # Try ISO8601 as fallback
      begin
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end

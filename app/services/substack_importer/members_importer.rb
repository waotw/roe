# frozen_string_literal: true

module SubstackImporter
  class MembersImporter
    attr_reader :import, :stats, :errors

    PLANS = {
      "lifetime" => :lifetime,
      "monthly" => :monthly,
      "quarterly" => :quarterly,
      "semiannually" => :semiannually,
      "yearly" => :yearly,
      "ios_app" => :ios_app,
      "comp" => :comp,
      "other" => :other
    }.freeze

    def initialize(import)
      @import = import
      @stats = {
        members_imported: 0,
        members_discarded: 0,
        members_updated: 0,
        members_by_plan: {},
        errors: []
      }
      @errors = []
    end

    def run
      Rails.logger.info "[SubstackImporter] Starting members import for import #{@import.id}"
      @import.update!(status: :importing_members, started_at: Time.current)
      Rails.logger.info "[SubstackImporter] Status updated to importing_members"

      csv_path = find_csv_file
      unless csv_path
        Rails.logger.info "[SubstackImporter] No email list found, skipping members import"
        @import.update!(
          status: :completed,
          stats: @import.stats.merge({ members_skipped_reason: "No email list found in export" }),
          completed_at: Time.current
        )
        @import.complete_phase!(3)
        return true
      end

      members = parse_csv(csv_path)
      Rails.logger.info "[SubstackImporter] Found #{members.count} members in CSV"

      # Filter members
      filtered_members = filter_members(members)
      Rails.logger.info "[SubstackImporter] After filtering: #{filtered_members.count} members to import"

      # Import each member
      Rails.logger.info "[SubstackImporter] Starting to process #{filtered_members.count} members..."
      filtered_members.each_with_index do |member_data, index|
        process_member(member_data)
        Rails.logger.info "[SubstackImporter] Processed member #{index + 1}/#{filtered_members.count}: #{member_data[:email]}" if (index + 1) % 100 == 0
      end
      Rails.logger.info "[SubstackImporter] Finished processing members. Stats: #{@stats.inspect}"

      # Update stats
      @import.update!(
        status: :completed,
        stats: @import.stats.merge(@stats),
        completed_at: Time.current
      )

      # Complete phase 3
      @import.complete_phase!(3)

      true
    rescue => e
      Rails.logger.error "[SubstackImporter] Members import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @import.mark_failed!(e.message)
      false
    end

    def rollback
      return false unless @import.can_rollback?

      Rails.logger.info "[SubstackImporter] Rolling back member import #{@import.id}"

      # Delete members created by this import
      members_deleted = ::Member.where(import: @import).count
      ::Member.where(import: @import).destroy_all

      @import.update!(status: :rolled_back)

      Rails.logger.info "[SubstackImporter] Rollback complete: #{members_deleted} members removed"

      { members_deleted: members_deleted }
    end

    private

    def reextract_archive
      archive_path = @import.archive_path
      extract_path = @import.extract_path

      unless archive_path && File.exist?(archive_path)
        Rails.logger.error "[SubstackImporter] Archive file not found: #{archive_path}"
        @errors << "Archive file not found"
        @import.mark_failed!("Cannot re-extract: archive file not found")
        return nil
      end

      begin
        # Re-extract the ZIP
        extractor = SubstackImporter::Extractor.new(archive_path, extract_path: extract_path)
        result = extractor.extract
        Rails.logger.info "[SubstackImporter] Re-extracted archive to: #{result}"
        result
      rescue => e
        Rails.logger.error "[SubstackImporter] Re-extraction failed: #{e.message}"
        @errors << "Re-extraction failed: #{e.message}"
        @import.mark_failed!("Failed to re-extract archive: #{e.message}")
        nil
      end
    end

    def find_csv_file
      extract_path = @import.extract_path
      Rails.logger.info "[SubstackImporter] Looking for CSV in: #{extract_path}"

      # If extract path doesn't exist, re-extract from archive
      if extract_path.nil? || !Dir.exist?(extract_path)
        Rails.logger.info "[SubstackImporter] Extract path missing, re-extracting archive..."
        extract_path = reextract_archive
        return nil unless extract_path
      end

      # Look for email_list CSV
      csv_files = Dir.glob(File.join(extract_path, "email_list*.csv"))
      Rails.logger.info "[SubstackImporter] Found CSV files: #{csv_files.inspect}"

      if csv_files.any?
        Rails.logger.info "[SubstackImporter] Using CSV: #{csv_files.first}"
        csv_files.first
      else
        # Also check for any CSV files
        all_csvs = Dir.glob(File.join(extract_path, "*.csv"))
        Rails.logger.info "[SubstackImporter] All CSV files in directory: #{all_csvs.inspect}"

        Rails.logger.info "[SubstackImporter] No email list CSV found, will skip members import"
        nil
      end
    end

    def parse_csv(csv_path)
      members = []
      first_row = true

      CSV.foreach(csv_path, headers: true) do |row|
        if first_row
          Rails.logger.info "[SubstackImporter] CSV Headers: #{row.headers.inspect}"
          Rails.logger.info "[SubstackImporter] First row data: #{row.to_h.inspect}"
          first_row = false
        end

        email = row["Email"] || row["email"] || row["EMAIL"]
        Rails.logger.debug "[SubstackImporter] Looking for email in columns. Found: '#{email}'"

        members << {
          email: email.to_s.downcase.strip,
          active_subscription: (row["active_subscription"] || row["Active Subscription"]).to_s.downcase == "true",
          expiry: (row["expiry"] || row["Expiry"]).presence,
          plan: (row["plan"] || row["Plan"]).to_s.downcase,
          email_disabled: (row["email_disabled"] || row["Email Disabled"]).to_s.downcase == "true",
          created_at: (row["created_at"] || row["Created At"]).presence,
          first_payment_at: (row["first_payment_at"] || row["First Payment At"]).presence
        }
      end

      Rails.logger.info "[SubstackImporter] Parsed #{members.count} members from CSV"
      members
    rescue => e
      Rails.logger.error "[SubstackImporter] CSV parsing failed: #{e.message}"
      @errors << "CSV parsing failed: #{e.message}"
      []
    end

    def filter_members(members)
      # All rows with an email are imported. `active_subscription` and
      # `email_disabled` are independent signals: tier comes from `plan`
      # (see determine_tier), newsletter subscription comes from
      # `email_disabled` (see process_member). A free member who turned
      # off emails is still a member — they just read on the site.
      members.reject { |m| m[:email].blank? }.tap do |kept|
        @stats[:members_discarded] = members.count - kept.count
      end
    end

    def process_member(member_data)
      email = member_data[:email].to_s.downcase.strip
      Rails.logger.debug "[SubstackImporter] Processing member: #{email}"

      # Extract name from email (everything before @)
      name = email.split("@").first

      # Find or initialize member
      member = ::Member.find_or_initialize_by(email: email)
      was_existing = member.persisted?

      Rails.logger.debug "[SubstackImporter] Member #{email} - existing: #{was_existing}"

      # Set/update basic fields
      member.name = name if member.name.blank?
      member.import = @import

      # Newsletter subscription
      member.newsletter_status = member_data[:email_disabled] ? :unsubscribed : :subscribed

      # Tier determination
      tier = determine_tier(member_data)
      member.tier = tier

      # Timestamps
      if member_data[:created_at].present?
        member.subscribed_at ||= Time.parse(member_data[:created_at])
      end

      if tier == :paid && member_data[:first_payment_at].present?
        member.paid_at ||= Time.parse(member_data[:first_payment_at])
      end

      # Store Substack metadata
      member.metadata ||= {}
      member.metadata["substack_plan"] = member_data[:plan]
      member.metadata["substack_active_subscription"] = member_data[:active_subscription]
      member.metadata["substack_first_payment_at"] = member_data[:first_payment_at]
      member.metadata["substack_expiry"] = member_data[:expiry]
      # Durable origin flag — survives even if the Import record is deleted
      # and the import_id FK gets nilled. The newsletter resend filters use
      # this as a backup so Substack-imported members are never sent a
      # Substack-originated newsletter twice.
      member.metadata["substack_imported"] = true
      member.metadata["substack_imported_at"] ||= Time.current.iso8601

      begin
        member.save!
        Rails.logger.info "[SubstackImporter] Successfully saved member: #{email}"

        # Update stats
        if was_existing
          @stats[:members_updated] += 1
          Rails.logger.info "[SubstackImporter] Updated existing member: #{email}"
        else
          @stats[:members_imported] += 1
          Rails.logger.info "[SubstackImporter] Created new member: #{email}"
        end

        # Track by plan
        plan = member_data[:plan].presence || "unknown"
        @stats[:members_by_plan][plan] ||= 0
        @stats[:members_by_plan][plan] += 1

        Rails.logger.info "[SubstackImporter] #{was_existing ? 'Updated' : 'Created'} member: #{email} (#{plan})"
      rescue => e
        Rails.logger.error "[SubstackImporter] Failed to save member #{email}: #{e.message}"
        Rails.logger.error "[SubstackImporter] Member errors: #{member.errors.full_messages.join(', ')}" if member.errors.any?
        @stats[:errors] << "#{email}: #{e.message}"
      end
    end

    def determine_tier(member_data)
      plan = member_data[:plan]
      return :free unless plan.present?

      options = @import.options || {}

      base_tier = case plan
      when "lifetime"
                    options["auto_gift_lifetime"] ? :paid : :free
      when "monthly", "quarterly", "semiannually", "yearly", "ios_app"
                    options["auto_gift_paid"] ? :paid : :free
      else  # comp, other, unknown
                    :free
      end

      # Only honor a paid grant if the Substack subscription is actually
      # effective right now. Without this, a lapsed monthly subscriber
      # (plan=monthly, active_subscription=false, expiry past) would still
      # be imported as paid just because their plan column says "monthly".
      return :free if base_tier == :paid && !subscription_effective?(member_data)

      base_tier
    end

    def subscription_effective?(member_data)
      return true if member_data[:active_subscription]

      expiry = member_data[:expiry]
      return false if expiry.blank?

      parsed = Time.parse(expiry) rescue nil
      parsed.present? && parsed > Time.current
    end
  end
end

# frozen_string_literal: true

# Restores a missing `status` on pages Roe itself installed.
#
# A page with no status is neither published nor unlisted, and
# SiteController#check_draft_access! 404s it for anyone not signed in. On
# installs from an earlier era that includes the Stripe return pages —
# checkout-success, checkout-cancel, donation-success, donation-cancel — so a
# customer finishing a payment lands on a 404. The site owner never sees it,
# because they're signed in.
#
# Those files predate the current templates (they carry a `member_page: true`
# key that has never existed in this codebase) and SiteTemplates::Loader skips
# anything already on disk, so they were never refreshed.
#
# Scope is deliberately narrow: only pages Roe ships a template for, and only
# when the installed file has no status at all. A page the user wrote without
# one is their business, and a status that merely disagrees with the template
# is a choice they made. Rewriting either would be an edit they didn't ask for
# — and would show up as Site Sync drift they didn't cause.
class PageStatusRepair
  Repair = Struct.new(:path, :status, keyword_init: true)

  TEMPLATE_ROOTS = [
    Rails.root.join("lib", "site_templates", "minimum", "pages"),
    Rails.root.join("lib", "site_templates", "features", "members", "pages")
  ].freeze

  class << self
    # Pages that need repairing, without touching anything.
    def pending
      Page.all.filter_map do |page|
        # The raw value, not #status — that reader defaults a missing status to
        # "draft", so it never reads as absent. The SQL scopes match the raw
        # JSON, which is why such a page belongs to no status scope and goes
        # missing from the dashboard's totals.
        next if page.metadata["status"].to_s.strip.present?

        status = template_status_for(page)
        next if status.blank?

        Repair.new(path: page.file_path, status: status)
      end
    end

    def pending?  = pending.any?
    def count     = pending.size

    # Writes the status into each file's front matter. Returns what it changed.
    def repair!
      repaired = pending.select { |r| apply(r) }
      ContentSync.new.sync_all if repaired.any?
      repaired
    end

    private

    # The status the shipped template gives this page, matched by the file's
    # path relative to /site — so only a page Roe put there can match.
    def template_status_for(page)
      relative = RoeSitePaths.normalize(page.file_path.to_s)
                             .sub(/\A#{Regexp.escape(RoeSitePaths::SITE_PATH.to_s)}\/?/, "")
      return nil if relative.blank?

      TEMPLATE_ROOTS.each do |root|
        candidate = File.join(root.to_s, relative.sub(%r{\Apages/}, ""))
        next unless File.exist?(candidate)

        front = FrontMatterParser::Parser.parse_file(candidate).front_matter
        return front["status"].to_s.presence
      end
      nil
    rescue StandardError => e
      Rails.logger.warn "[PageStatusRepair] couldn't read a template for #{page.file_path}: #{e.message}"
      nil
    end

    # Inserts `status:` into the existing front matter rather than rewriting
    # the file from parsed data — that would reformat everything else and turn
    # a one-line repair into a whole-file diff.
    def apply(repair)
      path = repair.path
      return false unless File.exist?(path)

      content = File.read(path)
      return false unless content.start_with?("---\n")
      return false if content.match?(/\A---\n.*?^status:/m)

      updated = content.sub(/\A---\n/, "---\nstatus: \"#{repair.status}\"\n")
      SiteFile.write(path, updated)
      Rails.logger.info "[PageStatusRepair] set status=#{repair.status} on #{path}"
      true
    rescue StandardError => e
      Rails.logger.warn "[PageStatusRepair] couldn't repair #{repair.path}: #{e.message}"
      false
    end
  end
end

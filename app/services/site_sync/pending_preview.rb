# frozen_string_literal: true

module SiteSync
  # A file the next sync will move, opened before the sync: what live holds
  # now, fetched on demand, beside the local file. Live's copy is downloaded
  # into a temporary folder (Exchange.download_files, the endpoint a pull
  # uses) and never written into /site.
  module PendingPreview
    # Big enough for any post, page, setting or theme, and most images.
    FETCH_MAX = 10 * 1024 * 1024

    module_function

    def local_path(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

    def local_copy(rel)
      abs = local_path(rel)
      File.file?(abs) ? abs : nil
    end

    # Live's copy of `rel` in a fresh temporary folder, or nil when live
    # doesn't have it, it's too large to fetch for a look, or live can't be
    # reached. The caller removes the folder (`with_live_copy` does).
    def with_live_copy(rel, size: nil)
      Dir.mktmpdir("roe-pending") do |dir|
        yield(size.to_i > FETCH_MAX ? nil : fetch(rel, dir))
      end
    end

    def fetch(rel, dir)
      bytes = Exchange.download_files([ rel ])
      return nil unless bytes

      TarArchive.unpack(bytes, dest: dir).include?(rel) ? File.join(dir, rel) : nil
    rescue StandardError => e
      Rails.logger.warn "[SiteSync::PendingPreview] live copy of #{rel}: #{e.class} #{e.message}"
      nil
    end

    # A relative path Site Sync tracks: inside /site and not excluded.
    def trackable?(rel)
      return false if rel.blank? || rel.include?("\0") || rel.start_with?("/")
      return false if Ledger.excluded?(rel)

      site = File.expand_path(RoeSitePaths::SITE_PATH)
      File.expand_path(File.join(site, rel)).start_with?(site + File::SEPARATOR)
    end
  end
end

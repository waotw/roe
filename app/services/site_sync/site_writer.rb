module SiteSync
  # Applies a received file set into a site root. Shared by the HTTP
  # transport's pull and the /api/site_sync/upload endpoint (the push
  # target), so both restore mtimes and apply deletions identically.
  #
  # Two jobs:
  #   - restore_mtimes: TarArchive deliberately doesn't carry mtime, so
  #     after unpacking we stamp each file's mtime from the accompanying
  #     per-file manifest. This makes size+mtime match the source and
  #     keeps the Ledger from flagging every just-synced file as drifted.
  #   - delete_paths: remove files the source no longer has. Defensive —
  #     refuses traversal/absolute/excluded paths so a sync message can
  #     never delete system/secrets/ or escape the site root.
  class SiteWriter
    class << self
      # manifest: { "rel/path" => { "size" =>, "mtime" => Integer }, ... }
      # Only entries whose file exists under `root` are touched.
      def restore_mtimes(root:, manifest:)
        Hash(manifest).each do |rel, meta|
          mtime = meta.is_a?(Hash) ? meta["mtime"] : nil
          next unless mtime

          full = File.join(root, rel.to_s)
          next unless File.file?(full)

          t = Time.at(mtime.to_i)
          File.utime(t, t, full)
        rescue => e
          Rails.logger.warn "[SiteSync::SiteWriter] could not set mtime on #{rel}: #{e.message}"
        end
      end

      # Delete each path (relative to `root`). Returns the paths actually
      # removed. Refuses traversal/absolute/Ledger-excluded paths so a
      # deletion list from a peer can never remove a secret/db file or
      # reach outside the site root.
      def delete_paths(root:, paths:)
        site_root = File.expand_path(root)

        Array(paths).each_with_object([]) do |rel, removed|
          rel = rel.to_s
          next if rel.include?("..") || rel.start_with?("/")
          # The guard stops a peer deleting anything we don't track — backups,
          # .git, secrets. Roe's own docs are the exception: a site set to
          # `local` excludes them from its manifest, so without this carve-out
          # it would refuse the very deletion that setting is asking for, and
          # stale copies would sit on live forever with nothing reporting them.
          next if Ledger.excluded?(rel) && !Ledger.roe_docs_path?(rel)

          full = File.expand_path(File.join(root, rel))
          next unless full.start_with?("#{site_root}/")

          if File.exist?(full)
            File.delete(full)
            removed << rel
          end
        rescue => e
          Rails.logger.warn "[SiteSync::SiteWriter] could not delete #{rel}: #{e.message}"
        end
      end
    end
  end
end

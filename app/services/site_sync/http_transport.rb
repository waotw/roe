module SiteSync
  # HTTP transport for Site Sync — the host-agnostic alternative to the
  # rsync-over-SSH transports (KamalRsync / FlyRsync). Moves file *bytes*
  # over the same HTTPS + bearer-token channel Exchange already uses for
  # cross-environment *state*, so a Roe instance can push/pull/back-up
  # content to any other Roe over port 443 with no SSH access.
  #
  # Mirrors the transport interface the rest of the app depends on:
  #   push_local_to_live!(diff:, on_progress:)
  #   pull_live_to_local!(diff:, on_progress:)
  #   backup_live_to_local!(files:, on_progress:)
  #
  # The wire primitive is one gzip'd tar per transfer (SiteSync::TarArchive)
  # rather than a request per file — batching is what keeps HTTP within
  # rsync's ballpark for Roe's workload (small text + wholesale media).
  #
  # NOTE ON SECRETS: system/secrets/ (and db/) never traverse this
  # channel in *either* direction — Ledger excludes them from every
  # manifest, the download endpoint refuses to serve them, and
  # TarArchive.unpack refuses to write them. So an HTTP backup is a
  # snapshot of syncable content, NOT an emergency key restore (that's
  # by design — dev and prod keep their own keys).
  #
  # Parallel-but-duplicated with the rsync transports, on purpose, per
  # the same reasoning noted in KamalRsync: keep them independent until
  # the shapes have settled in real-world use, then extract a base.
  class HttpTransport
    class HttpTransportError < StandardError; end

    # Cap each upload batch so a single request can't blow the transfer
    # timeout or balloon memory. A large first sync fans out into several
    # bounded requests; a small sync stays one batch (the fast path). A file
    # bigger than the byte cap still gets its own batch rather than being
    # split — the wire primitive is whole files.
    PUSH_BATCH_MAX_BYTES = 25 * 1024 * 1024
    PUSH_BATCH_MAX_FILES = 500

    class << self
      # ─── Push (local → live) ──────────────────────────────────────

      def push_local_to_live!(diff: nil, on_progress: nil)
        Rails.logger.info "[SiteSync::HttpTransport] push over HTTP → #{Exchange.peer_url}"
        diff ||= full_diff_for_push
        changed = changed_files(diff)
        deleted = Array(diff[:deleted])
        return if changed.empty? && deleted.empty?

        total = changed.size
        on_progress&.call(completed: 0, total: total)

        # Chunk into bounded batches. Deletions ride the LAST batch so the peer
        # only removes files after every new file has landed — a mid-push
        # failure leaves EXTRA files, never missing ones. Each batch retries
        # independently (transient network blips), peer writes are atomic, and
        # a fresh push recomputes its diff against the peer's current state — so
        # a re-run skips what already landed and converges without corruption.
        batches = batch_paths(changed)
        batches << [] if batches.empty? # deletions-only push still needs a call
        last = batches.length - 1
        done = 0

        batches.each_with_index do |paths, i|
          # Per-file size+mtime so the peer can restore mtimes after unpack.
          manifest = Ledger.current.slice(*paths)
          archive  = TarArchive.pack(root: RoeSitePaths::SITE_PATH, paths: paths)
          del      = (i == last) ? deleted : []

          Exchange.with_retries(label: "upload batch #{i + 1}/#{batches.length}") do
            result = Exchange.upload_files(archive_bytes: archive, manifest: manifest, deleted: del)
            raise HttpTransportError, "upload to peer failed" if result.nil?
          end

          done += paths.size
          on_progress&.call(completed: done, total: total)
        end

        # Match the rsync flow's post-push bookkeeping: rewrite the peer's
        # ledger (so its drift detection doesn't scream after the upload
        # touched mtimes) and reconcile its content rows to the new files.
        Exchange.refresh_peer_ledger!
        Exchange.reconcile_peer_content!
        true
      end

      # ─── Pull (live → local) ──────────────────────────────────────

      def pull_live_to_local!(diff: nil, on_progress: nil)
        Rails.logger.info "[SiteSync::HttpTransport] pull over HTTP ← #{Exchange.peer_url}"
        diff ||= full_diff_for_pull
        changed = changed_files(diff)
        deleted = Array(diff[:deleted])
        return if changed.empty? && deleted.empty?

        if changed.any?
          on_progress&.call(completed: 0, total: changed.size)

          # Fetch peer mtimes up front so we can stamp them after unpack, and
          # size the download batches (the local copy may not exist yet).
          states = Exchange.fetch_peer_file_states(changed)

          done = 0
          batches = batch_by_size(changed) { |rel| states.dig(rel, "size") }
          batches.each_with_index do |batch, i|
            bytes = nil
            Exchange.with_retries(label: "download batch #{i + 1}/#{batches.size}") do
              bytes = Exchange.download_files(batch)
              raise HttpTransportError, "download from peer failed" if bytes.nil?
            end

            written = TarArchive.unpack(bytes, dest: RoeSitePaths::SITE_PATH)
            SiteWriter.restore_mtimes(root: RoeSitePaths::SITE_PATH, manifest: states.slice(*written))

            done += written.size
            on_progress&.call(completed: done, total: changed.size)
          end
        end

        SiteWriter.delete_paths(root: RoeSitePaths::SITE_PATH, paths: deleted) if deleted.any?

        # We changed our own /site — rewrite our ledger so drift clears.
        Ledger.write_current!
        true
      end

      # ─── Backup (live → local, hardlinked) ────────────────────────
      #
      # Snapshots the live /site into ROE_ROOT/backups/live/content/
      # <timestamp>. Files unchanged since the previous snapshot are
      # hardlinked from it (File.link) instead of re-downloaded — same
      # bandwidth + storage economy as rsync's --link-dest. Only files
      # that actually differ are pulled over the wire.

      def backup_live_to_local!(files: nil, on_progress: nil)
        Rails.logger.info "[SiteSync::HttpTransport] backup over HTTP ← #{Exchange.peer_url}"
        peer = Exchange.fetch_peer_manifest
        raise HttpTransportError, "cannot back up live: peer manifest unavailable" unless peer

        peer_files = peer["files"] || {}
        wanted =
          if files
            requested = Array(files).uniq
            return nil if requested.empty?
            requested & peer_files.keys # selective: only files that exist live
          else
            peer_files.keys # full snapshot
          end
        return nil if wanted.empty?

        backup_dir, backup_root, timestamp = new_backup_dir
        previous = previous_backup(backup_root)
        FileUtils.mkdir_p(backup_dir)

        to_download = []
        linked = 0
        wanted.each do |rel|
          if previous && hardlink_reusable?(previous, rel, peer_files[rel])
            link_into(previous, backup_dir, rel)
            linked += 1
          else
            to_download << rel
          end
        end

        if to_download.any?
          downloaded = 0
          batches = batch_by_size(to_download) { |rel| peer_files.dig(rel, "size") }
          batches.each_with_index do |batch, i|
            bytes = nil
            Exchange.with_retries(label: "backup download batch #{i + 1}/#{batches.size}") do
              bytes = Exchange.download_files(batch)
              raise HttpTransportError, "backup download from peer failed" if bytes.nil?
            end

            written = TarArchive.unpack(bytes, dest: backup_dir)
            SiteWriter.restore_mtimes(root: backup_dir, manifest: peer_files.slice(*written))

            downloaded += written.size
            on_progress&.call(completed: linked + downloaded, total: wanted.size)
          end
        else
          on_progress&.call(completed: linked, total: wanted.size)
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      private

      # added + modified, de-duped and sorted — the set of files whose
      # bytes actually move (deletes are handled separately).
      def changed_files(diff)
        (Array(diff[:added]) + Array(diff[:modified])).uniq.sort
      end

      # Split paths into batches bounded by cumulative bytes and file count.
      # Preserves order; a single oversized file lands in its own batch rather
      # than being dropped or split.
      # Chunk paths into bounded batches by file count and total bytes. The
      # block yields each path's size — local file size for a push, the peer's
      # reported size for a download (the local copy may not exist yet).
      def batch_by_size(paths)
        batches = []
        current = []
        bytes   = 0

        paths.each do |rel|
          size = yield(rel).to_i
          if current.any? && (current.size >= PUSH_BATCH_MAX_FILES || bytes + size > PUSH_BATCH_MAX_BYTES)
            batches << current
            current = []
            bytes   = 0
          end
          current << rel
          bytes += size
        end

        batches << current if current.any?
        batches
      end

      def batch_paths(paths)
        batch_by_size(paths) { |rel| File.size?(File.join(RoeSitePaths::SITE_PATH, rel)) }
      end

      # Full push with no precomputed diff: diff local against the peer's
      # current manifest. If the peer is unreachable, treat every local
      # file as added (push everything, delete nothing) — a safe superset.
      def full_diff_for_push
        local = Ledger.current
        peer  = Exchange.fetch_peer_manifest
        Ledger.diff(local, peer ? peer["files"] : {})
      end

      # Full pull needs to know the peer's content; without the manifest
      # there's nothing to fetch, so fail loudly rather than silently
      # pulling nothing.
      def full_diff_for_pull
        peer = Exchange.fetch_peer_manifest
        raise HttpTransportError, "cannot pull: peer manifest unavailable" unless peer
        Ledger.diff(peer["files"] || {}, Ledger.current)
      end

      # ─── Hardlink backup helpers ──────────────────────────────────

      # A previous-snapshot file can be reused (hardlinked) only if it
      # matches the live file's size AND mtime — the same size+mtime test
      # the Ledger uses to decide "unchanged."
      def hardlink_reusable?(previous, rel, meta)
        return false unless meta.is_a?(Hash)

        prev_full = File.join(previous, rel)
        return false unless File.file?(prev_full) && !File.symlink?(prev_full)

        stat = File.stat(prev_full)
        stat.size == meta["size"].to_i && stat.mtime.to_i == meta["mtime"].to_i
      end

      def link_into(previous, backup_dir, rel)
        src = File.join(previous, rel)
        dst = File.join(backup_dir, rel)
        FileUtils.mkdir_p(File.dirname(dst))
        File.link(src, dst)
      rescue Errno::EEXIST
        # Already present (e.g. a retry) — leave it.
      rescue SystemCallError => e
        # Cross-device link or similar — fall back to a plain copy so the
        # snapshot is still complete, just without the dedup for this file.
        Rails.logger.warn "[SiteSync::HttpTransport] hardlink failed for #{rel} (#{e.message}); copying"
        FileUtils.cp(src, dst)
      end

      # ─── Backup dir scheme (mirrors KamalRsync) ───────────────────

      def new_backup_dir
        timestamp   = Time.now.strftime("%Y-%m-%d-%H%M%S")
        backup_root = SiteSync::BackupPaths.live_content
        FileUtils.mkdir_p(backup_root)
        backup_dir  = File.join(backup_root, timestamp)
        [ backup_dir, backup_root, timestamp ]
      end

      def previous_backup(backup_root)
        snapshots = Dir.glob(File.join(backup_root, "20*"))
                       .select { |d| File.directory?(d) && !File.symlink?(d) }
        snapshots.reject! { |d| Dir.empty?(d) rescue true }
        snapshots.sort.last
      end

      def update_latest_symlink(backup_root, timestamp)
        latest = File.join(backup_root, "latest")
        FileUtils.rm_f(latest) if File.symlink?(latest) || File.exist?(latest)
        FileUtils.ln_s(timestamp, latest)
      end
    end
  end
end

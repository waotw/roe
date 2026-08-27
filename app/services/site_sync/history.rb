# frozen_string_literal: true

module SiteSync
  # An append-only record of what each sync actually moved.
  #
  # The transfer job already computes this — every path it pushed, pulled or
  # deleted — and then writes it to a cache key that expires. So after a sync
  # there was no way to answer "what did that just do?", which mattered most in
  # the case you'd most want to answer it: a sync that removed files you wanted
  # back. The data was there and thrown away; this keeps it.
  #
  # Lives under backups/, not /site. A log inside /site would sync itself, and
  # its own writes would register as drift on every sync.
  #
  # JSONL, one object per sync event, paths only — a thousand syncs is a few
  # megabytes. Append-only and read newest-first.
  class History
    FILENAME = "sync-history.jsonl"
    KEEP     = 200

    # Each side of a sync, in the direction a person thinks about it.
    Direction = Struct.new(:changed, :deleted, keyword_init: true) do
      def any? = changed.any? || deleted.any?
      def count = changed.size + deleted.size
    end

    Event = Struct.new(:at, :kind, :outcome, :to_live, :to_local, :snapshot, :error,
                       keyword_init: true) do
      def any_changes? = to_live.any? || to_local.any?
      def total = to_live.count + to_local.count

      # The snapshot taken before this sync wrote anything locally — where a
      # file it deleted can still be found.
      def snapshot_name = snapshot.presence && File.basename(snapshot)

      # Snapshots are pruned, so a name in the log doesn't mean a directory on
      # disk. Offering a restore that can't work is worse than not offering it.
      def restorable?
        return false unless snapshot_name && to_local.any?

        Dir.exist?(File.join(SiteSync::BackupPaths.local, snapshot_name))
      end
    end

    class << self
      def path = File.join(SiteSync::BackupPaths.root, FILENAME)

      def exist? = File.exist?(path) && File.size(path).positive?

      # Never let recording a sync break a sync that worked.
      def record!(kind:, outcome:, to_live: {}, to_local: {}, snapshot: nil, error: nil, at: Time.current)
        entry = {
          "at"       => at.utc.iso8601,
          "kind"     => kind.to_s,
          "outcome"  => outcome.to_s,
          "to_live"  => normalize(to_live),
          "to_local" => normalize(to_local),
          "snapshot" => snapshot.presence,
          "error"    => error.presence
        }

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a") { |f| f.puts(JSON.generate(entry)) }
        trim!
        entry
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::History] couldn't record #{kind}: #{e.class} #{e.message}"
        nil
      end

      # Newest first.
      def recent(limit: KEEP)
        return [] unless exist?

        File.readlines(path).last(limit).reverse.filter_map { |line| parse(line) }
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::History] couldn't read history: #{e.class} #{e.message}"
        []
      end

      private

      def parse(line)
        raw = JSON.parse(line)
        Event.new(
          at:       (Time.zone.parse(raw["at"]) rescue nil),
          kind:     raw["kind"],
          outcome:  raw["outcome"],
          to_live:  direction(raw["to_live"]),
          to_local: direction(raw["to_local"]),
          snapshot: raw["snapshot"],
          error:    raw["error"]
        )
      rescue JSON::ParserError
        nil # a torn final line shouldn't lose the whole history
      end

      def direction(raw)
        raw ||= {}
        Direction.new(changed: Array(raw["changed"]).sort, deleted: Array(raw["deleted"]).sort)
      end

      # `modified` and `added` are one idea to whoever's reading this — the
      # file changed. Only deletions need to stand apart.
      def normalize(diff)
        diff = (diff || {}).symbolize_keys
        {
          "changed" => (Array(diff[:added]) + Array(diff[:modified])).uniq.sort,
          "deleted" => Array(diff[:deleted]).uniq.sort
        }
      end

      def trim!
        lines = File.readlines(path)
        return if lines.size <= KEEP

        File.write(path, lines.last(KEEP).join)
      end
    end
  end
end

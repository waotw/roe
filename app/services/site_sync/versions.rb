# frozen_string_literal: true

require "sqlite3"
require "digest"

module SiteSync
  # Every version of every file a sync replaces or deletes, so any change can
  # be put back.
  #
  #   backups/versions/
  #     history.sqlite3   one row per change: when, which path, which version
  #     objects/ab/cdef…  the contents, one file per version, named by SHA-256
  #
  # Contents are saved at the moment a version is replaced or deleted — the
  # local copy before a pull writes over it, live's copy (downloaded by the
  # pre-push backup) before a push does. The version a sync leaves is copied
  # too when it's small (AFTER_COPY_MAX); a large one is on disk and gets
  # copied when something replaces it. Identical contents are stored once,
  # however many times they turn up.
  #
  # Only on the computer that syncs: this lives in backups/, outside site/, so
  # it never travels. Opened directly with the sqlite3 gem rather than as a
  # Rails database — no migrations, created on first use, and an update that
  # rolls the app database back leaves it alone.
  #
  # Rules this keeps:
  #   1. Contents first, then the row, in one step. A crash leaves an unused
  #      copy (removed by the next trim), never a row pointing at nothing.
  #   2. Callers save before they delete or overwrite, and stop if saving fails
  #      (SaveFailed). No saved copy, no deletion.
  #   3. It records what a sync did; it never decides what a sync does.
  module Versions
    class SaveFailed < StandardError; end

    SCHEMA_VERSION = 1
    DEFAULT_DAYS   = 30
    DB_NAME        = "history.sqlite3"
    # The version a sync leaves is copied too when it's this size or under, so
    # "restore the site to after this sync" works even after a later local
    # edit that hasn't synced. Larger files (audio, video) are copied only when
    # something replaces them, so a new episode isn't stored twice.
    AFTER_COPY_MAX = 10 * 1024 * 1024

    module_function

    def root = File.join(SiteSync::BackupPaths.root, "versions")
    def db_path = File.join(root, DB_NAME)
    def objects_root = File.join(root, "objects")

    def object_path(sha)
      raise ArgumentError, "not a SHA-256: #{sha.inspect}" unless sha.to_s.match?(/\A\h{64}\z/)

      File.join(objects_root, sha[0, 2], sha[2..])
    end

    def object?(sha) = sha.present? && File.file?(object_path(sha))

    # Copy a file's contents into the store, hashing as it goes, and return
    # [sha, size]. Written to a temporary name and renamed into place, so a
    # stored object is always whole.
    def save_file(abs)
      tmp_dir = File.join(objects_root, ".tmp")
      FileUtils.mkdir_p(tmp_dir)
      tmp = File.join(tmp_dir, "#{Process.pid}-#{SecureRandom.hex(8)}")
      digest = Digest::SHA256.new
      size = 0
      File.open(abs, "rb") do |src|
        File.open(tmp, "wb") do |dst|
          while (chunk = src.read(1 << 20))
            digest << chunk
            dst.write(chunk)
            size += chunk.bytesize
          end
          dst.flush
          dst.fsync
        end
      end
      sha = digest.hexdigest
      dest = object_path(sha)
      if File.file?(dest)
        File.delete(tmp)
      else
        FileUtils.mkdir_p(File.dirname(dest))
        File.rename(tmp, dest)
      end
      [ sha, size ]
    rescue StandardError => e
      FileUtils.rm_f(tmp) if tmp
      raise SaveFailed, "couldn't save #{abs}: #{e.class} #{e.message}"
    end

    # The fingerprint of a file without storing it — for the version that
    # stays on disk.
    def fingerprint(abs)
      [ Digest::SHA256.file(abs).hexdigest, File.size(abs) ]
    end

    # The version a sync leaves: copied when small, fingerprinted when not.
    def keep_after(abs)
      File.size(abs) <= after_copy_max ? save_file(abs) : fingerprint(abs)
    end

    def after_copy_max = AFTER_COPY_MAX

    # One event and its changes, in one transaction. Each change is a hash:
    #   path:, direction: "to_live" | "to_local", action: "added" | "changed" | "deleted",
    #   before_sha:, before_size:, after_sha:, after_size:
    def record!(kind:, outcome:, at:, changes:)
      with_db do |db|
        event_id = nil
        db.transaction do
          db.execute("INSERT INTO events (at, kind, outcome) VALUES (?, ?, ?)",
                     [ at.utc.iso8601(3), kind.to_s, outcome.to_s ])
          event_id = db.last_insert_row_id
          changes.each do |c|
            db.execute(<<~SQL, [ event_id, c[:path], c[:direction].to_s, c[:action].to_s, c[:before_sha], c[:before_size], c[:after_sha], c[:after_size] ])
              INSERT INTO changes (event_id, path, direction, action, before_sha, before_size, after_sha, after_size)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            SQL
          end
        end
        event_id
      end
    end

    # Newest first: [{ id:, at:, kind:, outcome:, changes: [...] }]
    def events(limit: 100)
      return [] unless File.exist?(db_path)

      with_db do |db|
        rows = db.execute("SELECT id, at, kind, outcome FROM events ORDER BY id DESC LIMIT ?", [ limit ])
        rows.map do |id, at, kind, outcome|
          { id: id, at: Time.iso8601(at), kind: kind, outcome: outcome, changes: changes_for(db, id) }
        end
      end
    end

    # Every recorded change to one path, newest first, with its event's time.
    def history_of(path)
      return [] unless File.exist?(db_path)

      with_db do |db|
        db.execute(<<~SQL, [ path ]).map { |r| change_row(r) }
          SELECT c.id, c.event_id, e.at, c.path, c.direction, c.action, c.before_sha, c.before_size, c.after_sha, c.after_size
          FROM changes c JOIN events e ON e.id = c.event_id
          WHERE c.path = ? ORDER BY c.event_id DESC, c.id DESC
        SQL
      end
    end

    # Changes by id, oldest first, for undoing them. One path picked twice
    # keeps the earliest change's version: undoing both lands before both.
    def changes_by_id(ids)
      return [] if ids.empty? || !File.exist?(db_path)

      with_db do |db|
        marks = ([ "?" ] * ids.size).join(", ")
        rows = db.execute(<<~SQL, ids).map { |r| change_row(r) }
          SELECT c.id, c.event_id, e.at, c.path, c.direction, c.action, c.before_sha, c.before_size, c.after_sha, c.after_size
          FROM changes c JOIN events e ON e.id = c.event_id
          WHERE c.id IN (#{marks}) ORDER BY c.id DESC
        SQL
        rows.index_by { |c| c[:path] }.values
      end
    end

    # Which version each recorded path had just after `event_id`, as
    # { path => sha or nil (absent) }. A path's version at that point is the
    # one its next change replaced, or failing that, what its last change up to
    # then left. Paths with no recorded change aren't listed: they're as they
    # are on disk.
    def state_after(event_id)
      return {} unless File.exist?(db_path)

      with_db do |db|
        later = db.execute(<<~SQL, [ event_id ])
          SELECT path, before_sha FROM changes
          WHERE id IN (SELECT MIN(id) FROM changes WHERE event_id > ? GROUP BY path)
        SQL
        earlier = db.execute(<<~SQL, [ event_id ])
          SELECT path, after_sha FROM changes
          WHERE id IN (SELECT MAX(id) FROM changes WHERE event_id <= ? GROUP BY path)
        SQL
        earlier.to_h.merge(later.to_h)
      end
    end

    # How many days of history to keep: site.yml `sync_history_days`, 30 when
    # unset, 0 or "forever" for everything.
    def keep_days
      raw = SiteConfig.get("sync_history_days")
      return DEFAULT_DAYS if raw.nil? || raw.to_s.strip.empty?
      return nil if raw.to_s.strip.downcase == "forever"

      days = Integer(raw.to_s.strip, exception: false)
      return DEFAULT_DAYS if days.nil? || days.negative?

      days.zero? ? nil : days
    rescue StandardError
      DEFAULT_DAYS
    end

    # Drop events older than the cutoff, then every stored copy no remaining
    # row points to. A version inside the window stays rebuildable: it's either
    # the `before` of a change inside the window, or still on disk.
    def trim!(days: keep_days, now: Time.current)
      return unless File.exist?(db_path)

      with_db do |db|
        if days
          cutoff = (now - days.days).utc.iso8601(3)
          db.execute("DELETE FROM events WHERE at < ?", [ cutoff ])
        end
        keep = db.execute("SELECT before_sha FROM changes WHERE before_sha IS NOT NULL UNION SELECT after_sha FROM changes WHERE after_sha IS NOT NULL").flatten.to_set
        Dir.glob(File.join(objects_root, "??", "*")).each do |file|
          sha = File.basename(File.dirname(file)) + File.basename(file)
          File.delete(file) unless keep.include?(sha)
        end
        # Leftovers of a save that never finished.
        Dir.glob(File.join(objects_root, ".tmp", "*")).each do |file|
          File.delete(file) if File.mtime(file) < now - 1.day
        end
      end
    end

    def with_db
      FileUtils.mkdir_p(root)
      db = SQLite3::Database.new(db_path)
      db.busy_timeout = 10_000
      db.execute("PRAGMA journal_mode = WAL")
      db.execute("PRAGMA foreign_keys = ON")
      migrate!(db)
      yield db
    ensure
      db&.close
    end

    def migrate!(db)
      return if db.get_first_value("PRAGMA user_version").to_i >= SCHEMA_VERSION

      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS events (
          id      INTEGER PRIMARY KEY,
          at      TEXT NOT NULL,
          kind    TEXT NOT NULL,
          outcome TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS changes (
          id          INTEGER PRIMARY KEY,
          event_id    INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
          path        TEXT NOT NULL,
          direction   TEXT NOT NULL,
          action      TEXT NOT NULL,
          before_sha  TEXT,
          before_size INTEGER,
          after_sha   TEXT,
          after_size  INTEGER
        );
        CREATE INDEX IF NOT EXISTS changes_path   ON changes (path);
        CREATE INDEX IF NOT EXISTS changes_event  ON changes (event_id);
        CREATE INDEX IF NOT EXISTS changes_before ON changes (before_sha);
        CREATE INDEX IF NOT EXISTS changes_after  ON changes (after_sha);
        CREATE INDEX IF NOT EXISTS events_at      ON events (at);
        PRAGMA user_version = #{SCHEMA_VERSION};
      SQL
    end

    def changes_for(db, event_id)
      db.execute(<<~SQL, [ event_id ]).map { |r| change_row(r) }
        SELECT c.id, c.event_id, e.at, c.path, c.direction, c.action, c.before_sha, c.before_size, c.after_sha, c.after_size
        FROM changes c JOIN events e ON e.id = c.event_id
        WHERE c.event_id = ? ORDER BY c.path
      SQL
    end

    def change_row(r)
      id, event_id, at, path, direction, action, before_sha, before_size, after_sha, after_size = r
      { id: id, event_id: event_id, at: Time.iso8601(at), path: path, direction: direction, action: action,
        before_sha: before_sha, before_size: before_size, after_sha: after_sha, after_size: after_size }
    end
  end
end

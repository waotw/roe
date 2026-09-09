require "rubygems/package"
require "zlib"
require "stringio"
require "securerandom"

module SiteSync
  # The transfer primitive shared by the HTTP transport's push (upload) and
  # pull (download): pack a set of /site files into a gzip'd tar on one side,
  # unpack it on the other.
  #
  # `unpack` is security-hardened — it confines every entry to the destination
  # root (no `../` traversal, no absolute paths) and refuses to write any path
  # the Ledger excludes (system/secrets/, db/, …). So even a malicious or
  # buggy archive can't escape the sync root or clobber a production key.
  #
  # mtime is intentionally NOT carried here — the Ledger diffs on size+mtime,
  # so the transport restores each file's mtime from the accompanying per-file
  # manifest (File.utime) after unpacking. Keeping this primitive byte-only
  # makes it simple and independently testable.
  class TarArchive
    class UnsafeEntry < StandardError; end

    class << self
      # Pack `paths` (relative to `root`) into a gzip'd tar. Missing paths are
      # skipped (a file can vanish between diff and pack). Returns the bytes.
      def pack(root:, paths:)
        io = StringIO.new(+"".b)

        Zlib::GzipWriter.wrap(io) do |gz|
          Gem::Package::TarWriter.new(gz) do |tar|
            paths.each do |rel|
              full = File.join(root, rel)
              next unless File.file?(full) && !File.symlink?(full)

              stat = File.stat(full)
              tar.add_file_simple(rel, stat.mode & 0o777, stat.size) do |out|
                File.open(full, "rb") { |f| IO.copy_stream(f, out) }
              end
            end
          end
        end

        io.string
      end

      # Unpack a gzip'd tar into `dest`. Skips excluded paths; raises
      # UnsafeEntry on any entry that would escape `dest`. Returns the list of
      # written relative paths (sorted).
      def unpack(bytes, dest:)
        dest_root = File.expand_path(dest)
        written = []

        Zlib::GzipReader.wrap(StringIO.new(bytes)) do |gz|
          Gem::Package::TarReader.new(gz) do |tar|
            tar.each do |entry|
              next unless entry.file?

              rel = safe_relative_path(entry.full_name, dest_root)
              next if Ledger.excluded?(rel)

              target = File.join(dest_root, rel)
              FileUtils.mkdir_p(File.dirname(target))
              # Write to a temp file in the same directory, then atomically
              # rename into place. A crash or truncated stream mid-write can't
              # leave a half-written file at the real path (rename is atomic on
              # one filesystem) — worst case the file is simply re-sent next run.
              # gzip's trailing CRC/length catches a corrupt upload and raises
              # here, so a bad batch fails cleanly and only complete files land.
              tmp = "#{target}.sync-tmp-#{SecureRandom.hex(6)}"
              begin
                File.open(tmp, "wb") { |f| IO.copy_stream(entry, f) }
                File.rename(tmp, target)
              rescue
                FileUtils.rm_f(tmp)
                raise
              end
              written << rel
            end
          end
        end

        written.sort
      end

      # Returns the entry's path relative to dest_root, or raises if the entry
      # is absolute or resolves outside dest_root (path traversal).
      def safe_relative_path(name, dest_root)
        raise UnsafeEntry, "absolute path: #{name.inspect}" if name.start_with?("/")

        resolved = File.expand_path(File.join(dest_root, name))
        unless resolved == dest_root || resolved.start_with?("#{dest_root}/")
          raise UnsafeEntry, "entry escapes destination: #{name.inspect}"
        end

        resolved.delete_prefix("#{dest_root}/")
      end
    end
  end
end

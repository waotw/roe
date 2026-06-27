require "digest"
require "json"
require "find"

# Tracks per-file SHA256 + last_pushed_at for every file under
# `/static_site`. The push job uses this to decide what to send: anything
# whose current hash differs from the recorded one (or isn't recorded at
# all) is queued for upload; anything in the manifest but absent on disk
# is queued for remote deletion.
#
# Lives alongside `.generation_manifest.json` so both follow the same
# lifecycle — they ship with the static output.
#
# File-hash based rather than re-using the generation manifest's
# model_id-keyed shape because:
#   1. The generation manifest only tracks markdown-backed pages. Theme
#      CSS, fonts, copied assets, and computed feeds wouldn't show up.
#   2. SFTP is transport-agnostic — any disk change is a push candidate,
#      regardless of what produced it.
#   3. Decoupling from generation means a partial regen or external
#      tooling can still produce a correct push.
module StaticSiteSync
  class PushManifest
    MANIFEST_FILENAME = ".push_manifest.json"

    # Filesystem entries the push should ignore. The manifest itself is
    # excluded so writing it doesn't trigger a self-referential diff next
    # push. Dotfiles are skipped en masse — none of the SSG output needs
    # them and shared hosts often reject hidden uploads.
    EXCLUDED_BASENAMES = [ MANIFEST_FILENAME, ".DS_Store", ".generation_manifest.json" ].freeze

    Diff = Struct.new(:added, :modified, :deleted, keyword_init: true) do
      def empty? = added.empty? && modified.empty? && deleted.empty?
      def count = added.size + modified.size + deleted.size
      def upload_paths = added + modified
    end

    def initialize(root: RoeSitePaths::STATIC_SITE_PATH)
      @root = Pathname.new(root)
    end

    # Scan static_site/ → { "relative/path" => "sha256" }. Files only;
    # symlinks skipped (rare in SSG output, but avoid following any).
    def current_files
      return {} unless @root.directory?
      result = {}
      Find.find(@root.to_s) do |path|
        next unless File.file?(path) && !File.symlink?(path)
        basename = File.basename(path)
        next if EXCLUDED_BASENAMES.include?(basename)
        rel = Pathname.new(path).relative_path_from(@root).to_s
        result[rel] = Digest::SHA256.file(path).hexdigest
      end
      result
    end

    # Compare current disk state against the recorded manifest. Returns
    # a Diff with three disjoint path lists.
    def diff
      current = current_files
      recorded = read.fetch("files", {})

      added    = (current.keys - recorded.keys).sort
      deleted  = (recorded.keys - current.keys).sort
      modified = (current.keys & recorded.keys).select { |k| current[k] != recorded[k].dig("sha256") }.sort

      Diff.new(added: added, modified: modified, deleted: deleted)
    end

    # Was anything pushed yet?
    def empty?
      !manifest_path.exist? || read.fetch("files", {}).empty?
    end

    def last_pushed_at
      read["pushed_at"]&.then { |t| Time.parse(t) rescue nil }
    end

    # Replace the manifest with a snapshot of what's currently on disk,
    # stamped at `pushed_at`. Called after a successful push: at that
    # moment every file on disk has been sent, so the next diff against
    # this state correctly returns empty.
    def record_full_snapshot!(pushed_at: Time.current)
      hashes = current_files
      payload = {
        "pushed_at" => pushed_at.utc.iso8601,
        "files" => hashes.transform_values { |sha| { "sha256" => sha, "pushed_at" => pushed_at.utc.iso8601 } }
      }
      manifest_path.write(JSON.pretty_generate(payload))
    end

    # Update only the paths actually transferred, leaving every other
    # entry untouched. Lets a partial push (interrupted by network, user
    # cancel, etc.) make forward progress without claiming completeness
    # on files that didn't actually go.
    def record_partial_push!(uploaded_paths:, deleted_paths: [], pushed_at: Time.current)
      current = current_files
      data = read
      files = data.fetch("files", {})

      uploaded_paths.each do |rel|
        next unless current.key?(rel)
        files[rel] = { "sha256" => current[rel], "pushed_at" => pushed_at.utc.iso8601 }
      end
      deleted_paths.each { |rel| files.delete(rel) }

      data["files"] = files
      data["pushed_at"] = pushed_at.utc.iso8601
      manifest_path.write(JSON.pretty_generate(data))
    end

    def manifest_path
      @root.join(MANIFEST_FILENAME)
    end

    private

    def read
      return {} unless manifest_path.exist?
      JSON.parse(manifest_path.read)
    rescue JSON::ParserError
      {}
    end
  end
end

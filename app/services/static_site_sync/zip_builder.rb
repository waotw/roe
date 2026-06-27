require "zip"
require "find"
require "tempfile"

# Streams the contents of /static_site into a ZIP archive. Used by the
# "Download ZIP" action when the user has chosen ZIP as their deploy
# protocol — generated on demand, no async job, no remote credentials.
#
# Streams to the supplied IO so a Rails response can pipe it to the
# browser directly: never buffer the whole archive in memory. For a
# few-hundred-MB static site that matters.
module StaticSiteSync
  class ZipBuilder
    EXCLUDED_BASENAMES = PushManifest::EXCLUDED_BASENAMES

    def initialize(root: RoeSitePaths::STATIC_SITE_PATH)
      @root = Pathname.new(root)
    end

    # Write the archive to a temp file and return its Pathname. The
    # controller hands the temp path to `send_file`, which streams it
    # to the browser and ensures it's cleaned up at the end of the
    # request via the Tempfile finalizer.
    def build_tempfile
      tempfile = Tempfile.new([ "static_site_", ".zip" ], binmode: true)
      tempfile.close

      Zip::File.open(tempfile.path, create: true) do |zip|
        each_file do |abs_path, rel_path|
          zip.add(rel_path, abs_path)
        end
      end

      tempfile
    end

    # Count of files that will be included — surfaced in the UI so the
    # user can sanity-check before downloading ("Build will contain
    # 247 files").
    def file_count
      count = 0
      each_file { count += 1 }
      count
    end

    # Approximate byte size of the *source* tree (uncompressed). The
    # actual zip is smaller — for an HTML-heavy site, much smaller —
    # but this gives the UI a useful "things are this big" hint
    # without needing to actually run the build first.
    def estimated_uncompressed_bytes
      bytes = 0
      each_file { |abs| bytes += File.size(abs) }
      bytes
    end

    private

    def each_file
      return enum_for(:each_file) unless block_given?
      return unless @root.directory?

      Find.find(@root.to_s) do |path|
        next unless File.file?(path) && !File.symlink?(path)
        next if EXCLUDED_BASENAMES.include?(File.basename(path))
        rel = Pathname.new(path).relative_path_from(@root).to_s
        yield path, rel
      end
    end
  end
end

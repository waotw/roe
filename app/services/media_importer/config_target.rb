# A non-model rewrite target for the Media Importer — e.g. podcast.yml, whose
# `artwork` may be an external URL. Behaves enough like a content record for
# the scanner/rewriter (a file path + a metadata stub) but re-syncs itself via
# the given proc instead of ContentSync.
class MediaImporter::ConfigTarget
  attr_reader :file_path

  def initialize(file_path, resync:)
    @file_path = file_path
    @resync = resync
  end

  def metadata
    {}
  end

  def resync
    @resync.call
  end
end

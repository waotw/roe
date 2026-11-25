# Where a `/media/...` address is served from: site/media, then
# site/documentation/media, then each site/documentation/<scope>/media.
# MediaController serves from here and the links check asks here, so a file
# the check calls missing is one the site can't serve.
module MediaFiles
  module_function

  # The file a `/media/...` path (or the part after `/media/`) resolves to,
  # or nil. Only within the media folders: `/media/*path` is a public
  # wildcard route, so the path can hold "../" or glob characters. Each
  # candidate is expanded and must stay inside its folder, and the scope
  # folders are joined rather than globbed.
  def resolve(path)
    rel = path.to_s.delete_prefix("/media/")
    return nil if rel.empty?

    roots.each do |root|
      candidate = File.expand_path(File.join(root, rel))
      return candidate if within?(root, candidate) && File.file?(candidate)
    end
    nil
  end

  # Scope folders are read from disk, not from the request, so listing them
  # can't be steered.
  def roots
    site = RoeSitePaths::SITE_PATH
    list = [ File.join(site, "media"), File.join(site, "documentation", "media") ]

    docs = File.join(site, "documentation")
    if Dir.exist?(docs)
      Dir.children(docs).each do |scope|
        scope_media = File.join(docs, scope, "media")
        list << scope_media if Dir.exist?(scope_media)
      end
    end
    list
  end

  # `root` itself or below it. Roots get a trailing separator first, so
  # "/site/media-x" can't pass as "/site/media".
  def within?(root, path)
    root = File.expand_path(root)
    path == root || path.start_with?(root + File::SEPARATOR)
  end
end

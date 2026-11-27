# The files behind the URLs Roe serves from disk, and a short version for
# each that changes whenever the file does. VersionedFileUrls adds it to
# those URLs in every public page as ?v=, and FileValidators lets a request
# whose ?v= matches be cached for a year: the browser never asks again, and
# a changed file gets a new URL, so it's fetched straight away.
#
# The version comes from the file's size, inode and modification time, not
# its bytes, so a page with many images or a long video costs a stat per
# file, not a read. On disks with whole-second times (HFS+, FAT) a file
# replaced twice in one second at the same size keeps its version; the year
# cache is only used on live (Linux servers keep nanoseconds), and local
# keeps checking on every load.
module FileVersions
  # Path prefixes Roe serves files under, and where each one's files live.
  PREFIXES = %w[/media/ /system/images/ /system/fonts/ /theme/ /javascript/].freeze

  module_function

  # The file a URL path is served from, or nil when it isn't one of Roe's
  # file routes or the file doesn't exist. Mirrors the controllers'
  # resolution, including their guards against "../".
  def file_for(url_path)
    path = url_path.to_s
    if path.start_with?("/media/")
      MediaFiles.resolve(URI::DEFAULT_PARSER.unescape(path))
    elsif path.start_with?("/system/images/")
      in_folder(File.join(RoeSitePaths::SITE_PATH, "system", "assets", "images"), path.delete_prefix("/system/images/"))
    elsif path.start_with?("/system/fonts/")
      in_folder(File.join(RoeSitePaths::SITE_PATH, "system", "assets", "fonts"), path.delete_prefix("/system/fonts/"))
    elsif path.start_with?("/theme/")
      theme_file(path.delete_prefix("/theme/"))
    elsif path.start_with?("/javascript/")
      name = path.delete_prefix("/javascript/")
      file = SiteJavascript.path(name) if name == File.basename(name) && name.end_with?(".js")
      file if file && File.file?(file)
    end
  end

  # A short version for the file at path, or nil when it's missing.
  def version_for(file)
    stat = File.stat(file)
    Digest::MD5.hexdigest([ stat.size, stat.ino, stat.mtime.to_i, stat.mtime.nsec ].join("-"))[0, 12]
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  # The version for a URL path, or nil.
  def version_for_url(url_path)
    file = file_for(url_path)
    file && version_for(file)
  end

  def in_folder(folder, name)
    name = URI::DEFAULT_PARSER.unescape(name)
    return nil unless name.present? && name == File.basename(name)

    file = File.join(folder, name)
    file if File.file?(file)
  end

  # Site theme first, then the shipped one, as System::ThemesController does.
  def theme_file(name)
    return nil unless name == File.basename(name) && name.match?(/\.(css|js)\z/)

    [ File.join(RoeSitePaths::SITE_PATH, "theme", name), Rails.root.join("app", "themes", name).to_s ]
      .find { |file| File.file?(file) }
  end
end

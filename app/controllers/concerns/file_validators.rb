# Lets a browser reuse its copy of a file Roe serves from disk, without ever
# keeping a stale one.
#
# Every response says "no-cache": the browser must check before reusing its
# copy. The check carries an ETag and Last-Modified, so an unchanged file
# costs a 304 with no body instead of a full download. No max-age, on
# purpose: while editing, a cached copy could show an old image or stylesheet
# for that long.
#
# send_file responses get none of this from Rails: Rack::ETag skips file
# bodies and falls back to a bare "no-cache", which, with nothing to check
# against, makes the browser download every file again on every refresh.
module FileValidators
  extend ActiveSupport::Concern

  DIGEST_UP_TO = 512.kilobytes

  private

  # Sets the validators and Cache-Control for the file at path. Returns true,
  # having answered 304 Not Modified, when the browser's copy is current.
  #
  # private: true for files only some visitors may see (paid media), so no
  # shared cache between the site and the browser keeps a copy.
  #
  # Call it after any access check: a 304 still tells the visitor the file
  # exists and hasn't changed.
  def file_fresh?(path, private: false)
    stat = File.stat(path)
    fresh_when(strong_etag: file_etag(stat, path), last_modified: stat.mtime.utc, public: false)
    response.cache_control.replace(no_cache: true, extras: [ private ? "private" : "public" ])
    request.fresh?(response)
  end

  # The file's size, inode and modification time to the nanosecond. A file
  # replaced under the same name, a regenerated variant, or one Site Sync
  # rewrote gets a new value. Last-Modified only has whole seconds, so the
  # ETag is what the browser's check really turns on.
  #
  # Some disks (HFS+, FAT) keep whole seconds too, so a file saved twice in
  # one second at the same size (a CSS edit from "red" to "tan") would keep
  # its ETag. Small files add a digest of their bytes, which closes that gap
  # where it can happen; reading them is cheaper than sending them.
  def file_etag(stat, path)
    parts = [ stat.size, stat.ino, stat.mtime.to_i, stat.mtime.nsec ]
    parts << Digest::MD5.file(path).hexdigest if stat.size <= DIGEST_UP_TO
    parts.join("-")
  end

  # For a Range request: true when If-Range is absent or still matches the
  # file, so the slice comes from the copy the browser already has part of.
  # When it doesn't match, the whole new file is sent instead of a slice
  # that would mix old and new bytes.
  def if_range_matches?
    if_range = request.headers["If-Range"].to_s.strip
    return true if if_range.empty?

    # A weak ETag never matches here: a slice needs the exact same bytes.
    if if_range.start_with?("W/")
      false
    elsif if_range.start_with?('"')
      if_range == response.etag
    else
      if_range == response.last_modified&.httpdate
    end
  end
end

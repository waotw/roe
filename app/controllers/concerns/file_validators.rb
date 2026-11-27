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
#
# The exception is a request whose ?v= matches the file's current version
# (VersionedFileUrls puts it in every public page): that URL can only ever
# mean these bytes, because a changed file gets a new one, so it's cached
# for a year and the browser doesn't ask again. Only on live: local disks
# can keep whole-second times (HFS+), where two saves in one second at the
# same size would keep a version, and local is where editing happens.
module FileValidators
  extend ActiveSupport::Concern

  YEAR = 365 * 24 * 60 * 60

  mattr_accessor :year_cache, default: Rails.env.production?

  private

  # Sets the validators and Cache-Control for the file at path. Returns true,
  # having answered 304 Not Modified, when the browser's copy is current.
  #
  # private: true for files only some visitors may see (paid media), so no
  # shared cache between the site and the browser keeps a copy. Those never
  # get the year cache: a member whose access ends shouldn't keep the file.
  #
  # Call it after any access check: a 304 still tells the visitor the file
  # exists and hasn't changed.
  def file_fresh?(path, private: false)
    stat = File.stat(path)
    fresh_when(strong_etag: FileFingerprint.key(path, stat), last_modified: stat.mtime.utc, public: false)
    if !private && current_version_requested?(path)
      response.cache_control.replace(public: true, max_age: YEAR, extras: [ "immutable" ])
    else
      response.cache_control.replace(no_cache: true, extras: [ private ? "private" : "public" ])
    end
    request.fresh?(response)
  end

  # A ?v= that names the file as it is now. An old one (from a page opened
  # before the file changed) gets the normal check, so the new bytes are
  # never stored for a year under the old file's address.
  def current_version_requested?(path)
    FileValidators.year_cache && params[:v].present? && params[:v] == FileVersions.version_for(path)
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

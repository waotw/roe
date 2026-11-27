class MediaController < ApplicationController
  include FileValidators

  skip_before_action :require_authentication

  before_action :resolve_file
  before_action :authorize_media

  # authorize_media has already run, so a 304 is never an answer to a
  # visitor who may not see the file.
  def show
    return if file_fresh?(@file_path, private: protected_file?)

    range_header = request.headers["HTTP_RANGE"] || request.headers["Range"]
    return serve_whole_file unless range_header && if_range_matches?

    range = parse_range(range_header, @file_size)
    if range.nil?
      response.headers["Content-Range"] = "bytes */#{@file_size}"
      head :range_not_satisfiable
      return
    end

    serve_range(*range)
  end

  private

  def resolve_file
    @file_path = resolve_media_path(params[:path].to_s)
    return head :not_found unless @file_path

    @file_size = File.size(@file_path)
    @mime_type = Mime::Type.lookup_by_extension(File.extname(@file_path).delete_prefix(".")).to_s
    @mime_type = "application/octet-stream" if @mime_type.blank?
  end

  # Files referenced only by paid content aren't public. Everything else is
  # served exactly as before — most media is free and shouldn't pay for a
  # lookup it doesn't need, so the cached Medium#audience is checked first.
  #
  # Three ways through: an admin session, a signed-in paid member, or a
  # media_token belonging to one. The token is what makes podcast apps work —
  # they fetch enclosures with no cookies, so the URL has to carry its own
  # proof. It is NOT access_token: that one signs a member in.
  def authorize_media
    return unless protected_file?
    return if authenticated?
    return if current_member&.may_read_protected_media?
    return if member_from_media_token&.may_read_protected_media?

    head :forbidden
  end

  # Medium.protected_path? resolves a variant back to its source — variants
  # have no row of their own, so checking the requested path directly served
  # every resized copy of a paid image to anyone.
  def protected_file?
    return @protected_file if defined?(@protected_file)

    @protected_file = Medium.protected_path?(requested_media_path)
  end

  # The /media/... path as stored on Medium, rebuilt from the route wildcard.
  def requested_media_path
    "/media/#{params[:path]}"
  end

  def member_from_media_token
    token = params[:token].to_s.strip
    return nil if token.blank?

    Member.find_by(media_token: token)
  end

  def serve_whole_file
    response.headers["Accept-Ranges"] = "bytes"
    send_file @file_path, disposition: "inline", type: @mime_type
  end

  # Streams the requested slice instead of reading it into memory — the old
  # version called file.read(length), which for an album-sized download meant
  # holding the whole slice in the process.
  def serve_range(first, last)
    length = last - first + 1

    response.status = 206
    response.headers["Content-Range"]  = "bytes #{first}-#{last}/#{@file_size}"
    response.headers["Content-Length"] = length.to_s
    response.headers["Accept-Ranges"]  = "bytes"

    send_data_stream(first, length)
  end

  def send_data_stream(first, length)
    path = @file_path
    self.response_body = Enumerator.new do |chunk|
      File.open(path, "rb") do |file|
        file.seek(first)
        remaining = length
        while remaining > 0 && (buffer = file.read([ remaining, 64.kilobytes ].min))
          chunk << buffer
          remaining -= buffer.bytesize
        end
      end
    end
    response.headers["Content-Type"] = @mime_type
  end

  # Resolve a requested media path to a real file, but ONLY within the
  # allowed media roots (MediaFiles, which the links check shares). nil when
  # nothing safe matches.
  def resolve_media_path(rel)
    MediaFiles.resolve(rel)
  end

  def parse_range(range_header, file_size)
    # Expects format: "bytes=start-end" or "bytes=start-"
    match = range_header.match(/bytes=(\d*)-(\d*)/)
    return nil unless match

    first = match[1].present? ? match[1].to_i : 0
    last  = match[2].present? ? match[2].to_i : file_size - 1

    # Clamp to file bounds
    last = file_size - 1 if last >= file_size

    return nil if first > last || first >= file_size

    [ first, last ]
  end
end

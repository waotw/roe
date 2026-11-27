# A fingerprint for a file on disk that changes whenever the file does:
# the ETag Roe sends for media, theme CSS, site JS, fonts, system images and
# static-mode files.
#
# Size, inode and modification time to the nanosecond, so a file replaced
# under the same name, a regenerated variant, or one Site Sync rewrote gets
# a new value. Some disks (HFS+, FAT) keep whole seconds, so a file saved
# twice in one second at the same size (a CSS edit from "red" to "tan")
# would keep its value; small files add a digest of their bytes to close
# that gap, and reading them is cheaper than sending them.
module FileFingerprint
  DIGEST_UP_TO = 512 * 1024

  module_function

  # The raw parts, for Rails' strong_etag (which digests them itself).
  def key(path, stat = File.stat(path))
    parts = [ stat.size, stat.ino, stat.mtime.to_i, stat.mtime.nsec ]
    parts << Digest::MD5.file(path).hexdigest if stat.size <= DIGEST_UP_TO
    parts.join("-")
  end

  # A quoted strong ETag, for code outside a controller.
  def etag(path, stat = File.stat(path))
    %("#{Digest::MD5.hexdigest(key(path, stat))}")
  end
end

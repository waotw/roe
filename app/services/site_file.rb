# frozen_string_literal: true

# Writes a file only when its contents would actually change.
#
# Site Sync tracks changes on size + mtime, so rewriting a file with identical
# bytes reads as a real edit: "Refresh Sync Status" reports files changed that
# weren't, and the same file saved on both local and live ends up with matching
# content and two different timestamps — a difference the sync then can't
# resolve, because there's nothing to transfer.
#
# Config saves were the main source. Every writer in Admin::ConfigsController
# and the integration models rebuilt YAML and wrote it unconditionally, so
# opening a settings page and pressing Save with no edits bumped the mtime.
#
# A text editor doesn't write a file you opened and closed without changing.
# Roe shouldn't either.
#
# Reads before writing, which costs one stat + read of a small config file and
# saves a needless write plus everything that follows from it downstream.
class SiteFile
  # Returns true when the file was written, false when it already matched.
  def self.write(path, content)
    content = content.to_s
    return false unless changed?(path, content)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    true
  end

  # Same contract for a caller that wants to know without writing.
  #
  # Compared as bytes on both sides. File.binread returns ASCII-8BIT, and a
  # UTF-8 string holding the same bytes isn't == to it once anything outside
  # ASCII is involved — so an accented character in a config value would look
  # like a change on every save.
  def self.changed?(path, content)
    !File.exist?(path) || File.binread(path) != content.to_s.b
  end
end

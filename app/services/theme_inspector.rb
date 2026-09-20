# ThemeInspector
#
# The theme-flavoured face of ShippedFileInspector: bundled themes in
# app/themes/ against their installed copies in site/theme/. The header
# grammar, the status rules and the fingerprint all live there; this keeps
# the name the Themes page and its tests already use.
#
# A theme is "tracked" — eligible for in-place updates — only when:
#
#   1. The filename in site/theme/ matches a filename in app/themes/.
#      (User-renamed copies are custom themes.)
#   2. The installed file contains a parsable theme header.
#   3. The installed header's `Roe Theme:` value matches the bundled one.
#      (User-edited theme name is a custom theme.)
#
# Any deviation = custom = no update detection, no nags. With a
# Fingerprint line in the header, a tracked theme can also say whether its
# body was edited since install — see ShippedFileInspector.edited?.
class ThemeInspector
  HEADER_SCAN_BYTES = ShippedFileInspector::HEADER_SCAN_BYTES
  STATUSES          = ShippedFileInspector::STATUSES
  Header            = ShippedFileInspector::Header

  def self.parse_header(path)
    ShippedFileInspector.parse_header(path, kind: :theme)
  end

  def self.status(bundled_path:, installed_path:)
    ShippedFileInspector.status(bundled_path: bundled_path, installed_path: installed_path)
  end

  def self.report(bundled_path:, installed_path:)
    ShippedFileInspector.report(bundled_path: bundled_path, installed_path: installed_path)
  end

  def self.edited?(installed_path)
    ShippedFileInspector.edited?(installed_path)
  end

  def self.compare_versions(a, b)
    ShippedFileInspector.compare_versions(a, b)
  end
end

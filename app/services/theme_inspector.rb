# ThemeInspector
#
# Parses the version header comment that bundled Roe themes carry at the
# top of their CSS file, and computes update status by comparing a
# bundled theme (in app/themes/) against its installed copy (in
# site/theme/).
#
# A theme is considered "tracked" — i.e. eligible for in-place updates —
# only when ALL of these hold:
#
#   1. The filename in site/theme/ matches a filename in app/themes/.
#      (User-renamed copies are considered custom themes.)
#   2. The installed file contains a parsable theme header.
#   3. The installed header's `Roe Theme:` value matches the bundled
#      header's `Roe Theme:` value.
#      (User-edited theme name is considered a custom theme.)
#
# Any deviation = custom = no update detection, no nags.
#
# Header format (CSS block comment, anywhere in the first few hundred
# characters of the file — but conventionally line 1):
#
#   /* ============= THEME INFO =================
#      Roe Theme: Default
#      Version: 1.0.0
#      Bundled with: Roe v0.0.1
#      ...
#      ========================================== */
#
class ThemeInspector
  # Only scan the start of the file. Themes are small but we still don't
  # need to slurp the whole CSS just to read a header.
  HEADER_SCAN_BYTES = 2048

  Header = Struct.new(:name, :version, :bundled_with, keyword_init: true)

  # Status symbols returned by .status:
  #
  #   :tracked_current   — installed, matches bundled name, same version
  #   :tracked_outdated  — installed, matches bundled name, bundled is newer
  #   :tracked_ahead     — installed version is newer than bundled (e.g.
  #                        Roe was downgraded). Informational, no update.
  #   :custom            — filename matches but header is missing or
  #                        the "Roe Theme:" name doesn't match. Treat as
  #                        a custom theme — no nags, no in-place update.
  #   :not_installed     — bundled theme has no copy in site/theme/.
  #
  STATUSES = %i[tracked_current tracked_outdated tracked_ahead custom not_installed].freeze

  # Read the header from a CSS file. Returns a Header struct or nil if
  # the file doesn't exist, doesn't contain a recognisable header, or
  # the header is missing required fields.
  def self.parse_header(path)
    return nil unless path && File.exist?(path)

    head = File.read(path, HEADER_SCAN_BYTES)
    name         = head[/Roe Theme:\s*(.+)/, 1]&.strip&.presence
    version      = head[/Version:\s*([\d.]+)/, 1]&.strip&.presence
    bundled_with = head[/Bundled with:\s*(.+)/, 1]&.strip&.presence

    return nil unless name && version

    Header.new(name: name, version: version, bundled_with: bundled_with)
  end

  # Compute the update status for a bundled theme by comparing its header
  # against the installed copy's header. `bundled_path` is the file in
  # app/themes/; `installed_path` is the file in site/theme/.
  def self.status(bundled_path:, installed_path:)
    return :not_installed unless File.exist?(installed_path.to_s)

    bundled   = parse_header(bundled_path)
    installed = parse_header(installed_path)

    # No bundled header is unusual but means we can't compare anyway.
    return :custom unless bundled

    # Installed file has no parsable header OR its theme name was
    # changed → user has opted out of tracking.
    return :custom unless installed && installed.name == bundled.name

    case compare_versions(bundled.version, installed.version)
    when 0  then :tracked_current
    when 1  then :tracked_outdated
    when -1 then :tracked_ahead
    end
  end

  # Returns 1 if a > b, -1 if a < b, 0 if equal. Defensive against
  # mismatched component counts ("1.0" vs "1.0.0").
  def self.compare_versions(a, b)
    a_parts = a.to_s.split(".").map(&:to_i)
    b_parts = b.to_s.split(".").map(&:to_i)
    len = [ a_parts.length, b_parts.length ].max
    a_parts.fill(0, a_parts.length...len)
    b_parts.fill(0, b_parts.length...len)
    a_parts <=> b_parts
  end
end

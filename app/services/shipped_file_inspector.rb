# ShippedFileInspector
#
# Roe seeds a few files into site/ that the site then owns — the theme CSS
# in site/theme/, the front-end JS in site/javascript/. Each carries a
# header naming what it is, which version, and a fingerprint of the body
# below the header. From that, this answers one question per file: is the
# installed copy current, behind the shipped one, and if behind, has it
# been edited since it was installed?
#
# The last part is what the fingerprint buys. A version number alone says
# which shipped file the copy started as, not whether it was changed after
# — so an update would overwrite someone's edits without knowing. Hashing
# the body and writing the result into the header makes "edited?" a real
# question: hash what's on disk, compare to what the header claims.
#
# Header format (a block comment, conventionally at line 1):
#
#   /* ============= ROE SCRIPT ================
#      Roe Script: search
#      Version: 1.1.0
#      Fingerprint: 7f3a9c2e
#      Bundled with: Roe v0.4.0
#      ========================================= */
#
# Themes use "Roe Theme:" as the label; scripts "Roe Script:". Everything
# else is the same. The fingerprint is written by bin/sync-from-site (see
# ShippedFileInspector.stamp) and never by hand; a shipped file whose body
# changed without a version bump is caught there, before release.
#
# Statuses:
#
#   :not_installed      — no copy in site/
#   :custom             — installed copy has no parsable header, or the name
#                         was changed. The site has opted out; leave it be.
#   :tracked_current    — same version as shipped
#   :tracked_ahead      — installed version is newer (Roe was downgraded)
#   :tracked_outdated   — shipped is newer. Split by edited?:
#                           untouched → safe to update in place
#                           edited    → offer, never automatic
#
# Nothing here writes to site/. It reads and reports.
class ShippedFileInspector
  HEADER_SCAN_BYTES = 2048
  FINGERPRINT_LENGTH = 8

  KINDS = {
    theme:  { label: "Roe Theme",  banner: "THEME INFO" },
    script: { label: "Roe Script", banner: "ROE SCRIPT" }
  }.freeze

  STATUSES = %i[tracked_current tracked_outdated tracked_ahead custom not_installed].freeze

  Header = Struct.new(:name, :version, :bundled_with, :fingerprint, keyword_init: true)

  # Files Roe shipped before headers existed, by the fingerprint of their
  # body. A site copy with no header whose body matches one of these is
  # that release's file, untouched — not a custom file — so the page can
  # offer the update instead of leaving it alone forever. The version is
  # what that copy would have carried had it been stamped; "0" for a file
  # that predates versioning, so any shipped version reads as newer.
  #
  # This list is closed: nothing ships without a header any more, so
  # nothing is ever added to it.
  LEGACY = {
    # nightly.3 and earlier
    "11638bf0" => { name: "search",    version: "1.0.0" },
    "bf9190e1" => { name: "gallery",   version: "0" },
    "9752c470" => { name: "checkout",  version: "0" },
    "dbfead60" => { name: "footnotes", version: "0" },
    # nightly.4: search.js with the new index format but no header
    "6992fc4e" => { name: "search",    version: "1.0.1" },
    # themes at 0.3.0, before Fingerprint was added to the header
    "e9ea980a" => { name: "Default",   version: "0.1.0" },
    "b7c51a9d" => { name: "Bare",      version: "0.1.1" }
  }.freeze

  # Everything the admin needs to show one row.
  Report = Struct.new(:status, :edited, :bundled, :installed, keyword_init: true) do
    def update_available? = status == :tracked_outdated
    def safe_to_update?   = update_available? && !edited
  end

  def self.parse_header(path, kind: nil)
    return nil unless path && File.exist?(path)

    head  = File.read(path, HEADER_SCAN_BYTES)
    label = kind ? KINDS.fetch(kind)[:label] : KINDS.values.map { |k| k[:label] }.join("|")
    name         = head[/(?:#{label}):\s*(.+)/, 1]&.strip&.presence
    version      = head[/Version:\s*([\d.]+)/, 1]&.strip&.presence
    bundled_with = head[/Bundled with:\s*(.+)/, 1]&.strip&.presence
    fingerprint  = head[/Fingerprint:\s*([0-9a-f]+)/i, 1]&.strip&.downcase&.presence

    return legacy_header(path) unless name && version

    Header.new(name: name, version: version, bundled_with: bundled_with, fingerprint: fingerprint)
  end

  # The header a pre-header shipped file would have carried. Its
  # fingerprint is the body's own, so edited? reads false — the copy is,
  # by construction, exactly what Roe shipped.
  def self.legacy_header(path)
    fp = fingerprint(path)
    entry = fp && LEGACY[fp]
    return nil unless entry

    Header.new(name: entry[:name], version: entry[:version], bundled_with: nil, fingerprint: fp)
  end

  # Hash of the file with its header block removed, so the header's own
  # Version/Fingerprint lines can change without changing the answer.
  def self.fingerprint(path)
    return nil unless path && File.exist?(path)

    fingerprint_of(File.read(path))
  end

  def self.fingerprint_of(content)
    Digest::SHA256.hexdigest(body_of(content))[0, FINGERPRINT_LENGTH]
  end

  # True when the installed copy's body no longer matches the fingerprint
  # in its own header. A header with no Fingerprint line (a theme installed
  # before fingerprints existed) is checked against the LEGACY table of
  # shipped bodies instead; a match means untouched. Anything that can't
  # be judged reports as edited — the cautious answer, since the cost of
  # being wrong is someone's work.
  def self.edited?(installed_path)
    header = parse_header(installed_path)
    return true unless header

    actual = fingerprint(installed_path)
    return actual != header.fingerprint if header.fingerprint

    !LEGACY.key?(actual)
  end

  def self.status(bundled_path:, installed_path:)
    return :not_installed unless File.exist?(installed_path.to_s)

    bundled   = parse_header(bundled_path)
    installed = parse_header(installed_path)

    return :custom unless bundled
    return :custom unless installed && installed.name == bundled.name

    case compare_versions(bundled.version, installed.version)
    when 0  then :tracked_current
    when 1  then :tracked_outdated
    when -1 then :tracked_ahead
    end
  end

  def self.report(bundled_path:, installed_path:)
    s = status(bundled_path: bundled_path, installed_path: installed_path)
    Report.new(
      status:    s,
      edited:    (s == :tracked_outdated || s == :tracked_current) ? edited?(installed_path) : nil,
      bundled:   parse_header(bundled_path),
      installed: parse_header(installed_path)
    )
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

  # ── Release-time stamping (bin/sync-from-site) ─────────────────────────

  # Every shipped file this applies to, as absolute paths under current/.
  def self.shipped_files
    Dir.glob(Rails.root.join("app", "themes", "*.css").to_s) +
      Dir.glob(Rails.root.join("app", "site_js", "*.js").to_s)
  end

  # The pre-release guard. For each shipped file: if its body changed since
  # the last commit but its Version didn't, that's a change no site would
  # ever be offered — say so and fail. Otherwise stamp the fingerprint so
  # the header matches the body that ships. Prints a line per file; returns
  # true when everything is in order.
  #
  # `site_root:` runs the same check against a site's copies instead —
  # bin/sync-from-site stamps there BEFORE copying into current/, so the
  # developer's site and the shipped file agree and the Themes page on the
  # dev install doesn't call its own work "edited". The comparison is
  # still against the committed copy in current/.
  def self.check_release!(out: $stdout, site_root: nil)
    ok = true
    shipped_files.sort.each do |path|
      rel    = path.sub("#{Rails.root}/", "")
      target = site_root ? site_path_for(rel, site_root) : path
      next unless File.exist?(target)

      header = parse_header(target)
      unless header
        out.puts "    #{rel}: no header — add one (Roe Script/Theme, Version)"
        ok = false
        next
      end

      committed = committed_content(rel)
      if committed
        old_header  = header_from_content(committed)
        old_fp      = fingerprint_of(committed)
        new_fp      = fingerprint_of(File.read(target))
        if old_header && old_fp != new_fp && old_header.version == header.version
          out.puts "    #{rel}: body changed but Version is still #{header.version} — bump it"
          ok = false
          next
        end
      end

      case stamp!(target)
      when :stamped   then out.puts "    #{rel}: v#{header.version}, fingerprint stamped"
      when :unchanged then out.puts "    #{rel}: v#{header.version}, up to date"
      end
    end
    ok
  end

  # Where a shipped file lives in a site: app/themes/x.css → site/theme/x.css,
  # app/site_js/x.js → site/javascript/x.js.
  def self.site_path_for(rel, site_root)
    name = File.basename(rel)
    dir  = rel.start_with?("app/themes/") ? "theme" : "javascript"
    File.join(site_root, dir, name)
  end

  def self.committed_content(rel)
    content = `git -C #{Shellwords.escape(Rails.root.to_s)} show HEAD:#{Shellwords.escape(rel)} 2>/dev/null`
    $?.success? ? content : nil
  end

  def self.header_from_content(content)
    head = content[0, HEADER_SCAN_BYTES]
    name    = head[/(?:Roe Theme|Roe Script):\s*(.+)/, 1]&.strip&.presence
    version = head[/Version:\s*([\d.]+)/, 1]&.strip&.presence
    name && version ? Header.new(name: name, version: version) : nil
  end

  # Rewrite the Fingerprint line in a shipped file to match its body.
  # Returns :stamped, :unchanged, or :no_header. Only ever run on the
  # shipped copies in current/, never on a site's.
  def self.stamp!(path)
    content = File.read(path)
    header_end = header_end_index(content)
    return :no_header unless header_end

    fp = fingerprint_of(content)
    head, body = content[0...header_end], content[header_end..]
    if head =~ /Fingerprint:\s*[0-9a-f]*/i
      new_head = head.sub(/Fingerprint:\s*[0-9a-f]*/i, "Fingerprint: #{fp}")
    else
      # Insert after the Version line, matching its indentation.
      new_head = head.sub(/^(\s*)(Version:.*)$/) { "#{$1}#{$2}\n#{$1}Fingerprint: #{fp}" }
    end
    return :unchanged if new_head == head

    File.write(path, new_head + body)
    :stamped
  end

  # The body used for fingerprinting: the file with its header comment
  # removed. A file with no header block is fingerprinted whole.
  def self.body_of(content)
    i = header_end_index(content)
    i ? content[i..] : content
  end

  # Index just past the closing */ of the header comment, or nil.
  def self.header_end_index(content)
    return nil unless content.lstrip.start_with?("/*")

    close = content.index("*/")
    close && close + 2
  end
end

# Canonical resolution for the fixed layout files (header, footer, sidebar).
#
# `header` supersedes the legacy `navigation.md`: both names point at the same
# slot (the top position), `header.md` wins, and a one-time migration renames
# navigation → header so header is canonical going forward. The read-fallback
# means an old `navigation.md` (e.g. arriving via Site Sync) still works.
module LayoutFiles
  # name => filenames to try, in preference order (first is canonical for writes)
  NAMES = {
    "header"     => %w[header navigation],
    "navigation" => %w[header navigation], # alias for legacy callers
    "footer"     => %w[footer],
    "sidebar"    => %w[sidebar]
  }.freeze

  KEYS = %w[header footer sidebar].freeze

  module_function

  def dir
    File.join(RoeSitePaths::SITE_PATH, "layout")
  end

  # The existing file for `name`, or its canonical path when none exists yet.
  def path(name)
    candidates(name).map { |n| File.join(dir, "#{n}.md") }.find { |p| File.exist?(p) } ||
      File.join(dir, "#{candidates(name).first}.md")
  end

  def exist?(name)
    candidates(name).any? { |n| File.exist?(File.join(dir, "#{n}.md")) }
  end

  def candidates(name)
    NAMES[name.to_s] || [ name.to_s ]
  end

  # One-time: rename navigation.md → header.md so header is canonical. Safe and
  # idempotent — only fires when the old file is there and the new one isn't.
  def migrate_navigation_to_header!
    nav    = File.join(dir, "navigation.md")
    header = File.join(dir, "header.md")
    return unless File.exist?(nav) && !File.exist?(header)

    File.rename(nav, header)
    Rails.logger.info "[LayoutFiles] Renamed navigation.md → header.md"
  rescue => e
    Rails.logger.warn "[LayoutFiles] navigation→header migration skipped: #{e.class} #{e.message}"
  end
end

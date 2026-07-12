module SiteSyncHelper
  # Path prefixes that Roe manages wholesale: an update rewrites every file
  # underneath them, so listing 59 individual "changes" the user never made
  # is just noise on the Site Sync page. Each prefix collapses to a single
  # display row. DISPLAY ONLY — the actual sync still diffs and transfers
  # every file; this only tidies what the admin sees.
  SYNC_DISPLAY_GROUPS = {
    "documentation/roe" => "Roe documentation"
  }.freeze

  # Collapse a list of /site-relative paths for display. Any path under a
  # SYNC_DISPLAY_GROUPS prefix folds into one "<Label> — N files changed"
  # row; every other path passes through unchanged. Returns an array of
  # display strings, so callers can use `.size` for a collapsed count and
  # iterate it for the detail rows — a drop-in for a raw path list.
  def collapse_sync_paths(paths)
    grouped = Hash.new(0)
    singles = []

    Array(paths).each do |path|
      prefix = SYNC_DISPLAY_GROUPS.keys.find { |p| path.to_s == p || path.to_s.start_with?("#{p}/") }
      if prefix
        grouped[prefix] += 1
      else
        singles << path
      end
    end

    group_rows = grouped.map do |prefix, n|
      "#{SYNC_DISPLAY_GROUPS[prefix]} — #{n} file#{'s' unless n == 1} changed"
    end

    group_rows.sort + singles.sort
  end

  # Collapsed count for a raw path list — the number of rows the user
  # actually sees (grouped prefixes count as one). Used for the summary
  # tallies so "59 modified" reads as "1 modified".
  def collapsed_sync_count(paths)
    collapse_sync_paths(paths).size
  end
end

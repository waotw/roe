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

  # The terminal command to restart the LIVE app from the operator's LOCAL
  # machine (production can't restart itself), run from inside the Rails-app
  # dir where the deploy config lives. Uses the peer's deploy target +
  # rails_subdir synced over the handshake (SyncConfig#peer_*). The user first
  # navigates to the Roe folder (see the _restart_instructions partial); this
  # is step 2 — cd into the app subdir, then boot.
  def restore_restart_command(config)
    base = config&.peer_deploy_target == "fly" ? "fly deploy" : "kamal app boot"
    subdir = config&.peer_rails_subdir.presence
    subdir ? "cd #{subdir} && #{base}" : base
  end

  # Display label for the peer's Roe folder, with a friendly fallback when we
  # haven't learned it over a sync yet.
  def restore_roe_folder_label(config)
    config&.peer_folder_name.presence || "your Roe folder"
  end

  # True when this site is running on Fly (keys live in Fly secrets, not files),
  # so credential recovery uses `roe:fly:sync_secrets` instead of an apply-file
  # flow.
  def running_on_fly?
    ENV["FLY_APP_NAME"].present?
  end

  # The command that re-pushes this Fly app's encryption keys from the local
  # install's credentials (no keys are handled by hand). Run from the Rails-app
  # subdir on the operator's local machine.
  def fly_sync_secrets_command(config, app_name)
    app    = app_name.presence || "your-fly-app"
    subdir = config&.peer_rails_subdir.presence
    cmd    = "bin/rails roe:fly:sync_secrets APP=#{app}"
    subdir ? "cd #{subdir} && #{cmd}" : cmd
  end
end

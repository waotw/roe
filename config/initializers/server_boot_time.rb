# Capture the Puma process's boot time once, at initializer load.
# Persisted on Rails.application.config so it survives autoreload
# (initializers don't re-run between requests) and only resets when
# the Puma process itself is killed and relaunched.
#
# Used by Admin::UpdatesController#index to distinguish:
#
#   completed_at > server_boot_time
#     → the update finished inside THIS Puma process → user still
#       needs to do a manual restart → show the blue "Restart Roe"
#       panel with terminal instructions.
#
#   completed_at < server_boot_time
#     → the update finished BEFORE this process started → Puma has
#       been relaunched on the new code → show the green
#       "Update Successful" panel.
#
# Comparing against `VersionChecker.current_version` (the previous
# approach) was unreliable because Rails dev autoreload may or may
# not reload version_checker.rb depending on whether its file content
# changed between the two tags — leading to the new code running but
# the memoized @current_version showing the old value, or vice versa.
# Boot time is a process-level signal that doesn't lie either way.
Rails.application.config.server_boot_time = Time.current

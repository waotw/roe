class Admin::UpdatesController < Admin::BaseController
  # Updates and deploys happen from the user's LOCAL Roe install, not from
  # the live admin. The in-app updater swaps files in current/, which a
  # production container's immutable image layer can't honour (and even if
  # it did, there's no git in the production image to clone from). And
  # deploys obviously can't be triggered from inside the deployed instance.
  # Block every action here in production so anyone who lands on this
  # route (typed URL, stale bookmark, old link) gets a clear redirect
  # back to the dashboard instead of a stale or broken page.
  # Block mutating actions in production — the in-app updater swaps files
  # in current/, which an immutable container image can't do, and deploys
  # can't be triggered from inside the deployed instance. The page itself
  # (index + read-only status routes) is still reachable so production
  # users can see "an update is available" and know to run the update from
  # their local install. The view surfaces a production-mode notice.
  before_action :block_in_production, only: %i[
    start rollback start_deploy reset_and_retry_deploy dismiss_deploy
  ]
  before_action :block_on_dev_install, only: %i[start rollback]

  def index
    @current_version    = RoeUpdater::VersionChecker.current_version
    @dev_install        = RoeUpdater::VersionChecker.dev_install?
    @update_channel     = SiteConfig.get("update_channel").to_s.presence || "stable"
    @prerelease_channel = RoeUpdater::VersionChecker.prerelease_channel?
    @update_info        = RoeUpdater::VersionChecker.check_for_updates
    @last_update        = UpdateStatus.order(created_at: :desc).first
    @in_progress        = UpdateStatus.where(status: "in_progress").exists?

    # Post-update display state. The version-status block at the top
    # of the page picks one of: amber in-progress / blue restart-needed
    # / green just-updated / blue update-available / green up-to-date.
    #
    # Detection signal: compare @last_update.completed_at against the
    # Puma process's boot time (captured once in
    # config/initializers/server_boot_time.rb, persists across Rails
    # autoreload, resets only on a real Puma restart).
    #
    #   completed_at > boot_time → update finished IN this process,
    #                              user still needs to restart Puma →
    #                              show blue "Restart Roe" panel.
    #   completed_at < boot_time → update finished BEFORE this process
    #                              started, so Puma has already been
    #                              relaunched on the new code →
    #                              show green "Update Successful" panel.
    #
    # This replaces an older version-comparison approach that was
    # unreliable because Rails autoreload may or may not refresh
    # VersionChecker's memoized current_version, depending on whether
    # the file's content changed between tags.
    @recent_update = @last_update &&
                     @last_update.status == "completed" &&
                     @last_update.completed_at.present? &&
                     @last_update.completed_at > 5.minutes.ago
    @restart_pending  = false
    @restart_complete = false
    if @recent_update
      boot_time = Rails.application.config.server_boot_time
      @restart_pending  = boot_time && @last_update.completed_at >= boot_time
      @restart_complete = boot_time && @last_update.completed_at <  boot_time
    end

    # Deploy section
    @deploy_status       = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    @last_deploy_time    = load_last_deploy_time
    @deploy_config       = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    @deploy_issues       = deploy_prerequisites(@deploy_config)
    @fly_cli_available   = DeployConfigGenerator.fly_cli_available?
    @kamal_cli_available = DeployConfigGenerator.kamal_cli_available?

    # Deploy display helpers
    @default_app_name    = File.basename(RoeSitePaths::ROE_ROOT).presence || "roe"
    @deploy_target       = @deploy_config["target"].presence || "kamal"
    @deploy_target_label = @deploy_target == "kamal" ? "Kamal" : "Fly.io"
    @deploy_server_desc  = deploy_server_description(@deploy_config, @deploy_target, @default_app_name)
    @deploy_confirm_msg  = deploy_confirmation_message(@deploy_target, @deploy_server_desc, @deploy_config, @default_app_name)
  end

  def check
    RoeUpdater::VersionChecker.clear_cache
    @update_info = RoeUpdater::VersionChecker.check_for_updates

    if @update_info
      flash[:notice] = "Update check completed"
    else
      flash[:alert] = "Could not check for updates. Please try again later."
    end

    redirect_to admin_updates_path
  end

  def start
    version = params[:version]

    if UpdateStatus.where(status: "in_progress").exists?
      flash[:alert] = "An update is already in progress. Please wait for it to complete."
      redirect_to admin_updates_path
      return
    end

    unless license_valid?
      flash[:alert] = "License expired. Please renew to update."
      redirect_to admin_updates_path
      return
    end

    # Create the UpdateStatus eagerly, BEFORE redirecting. Solid Queue
    # may take a second or two to pick up the enqueued job — if the
    # job were the one creating the record (the old flow), the page
    # would re-render with @in_progress = false, no in-progress
    # panel, and no JS polling target. The user would see a stale
    # "Update Available" panel with no indication anything was
    # happening. Creating it here means the next render shows the
    # amber in-progress panel immediately and Stimulus polling
    # starts on first paint.
    status = UpdateStatus.create!(
      status:           "in_progress",
      from_version:     RoeUpdater::VersionChecker.current_version,
      to_version:       version,
      current_step:     "Queued — waiting for worker…",
      progress_percent: 0,
    )

    PerformUpdateJob.perform_later(version: version, status_id: status.id)

    flash[:notice] = "Update to v#{version} started. This may take a few minutes."
    redirect_to admin_updates_path
  end

  def status
    update_status = UpdateStatus.order(created_at: :desc).first

    render json: {
      status:   update_status&.status,
      step:     update_status&.current_step,
      progress: update_status&.progress_percent,
      error:    update_status&.error_message,
      log:      update_status&.log
    }
  end

  def rollback
    if SwitchManager.rollback
      flash[:notice] = "Rollback completed successfully. Please restart the server."
    else
      flash[:alert] = "Rollback failed. Please check the logs and contact support."
    end

    redirect_to admin_updates_path
  end

  # ── Deploy actions ────────────────────────────────────────────────────────

  def start_deploy
    if Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)&.dig(:state) == :running
      flash[:alert] = "A deploy is already in progress. Wait for it to finish."
      redirect_to admin_updates_path
      return
    end

    config  = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    issues  = deploy_prerequisites(config)

    if issues.any?
      flash[:alert] = "Deploy is not ready: #{issues.to_sentence}."
      redirect_to admin_updates_path
      return
    end

    target      = config["target"].presence || "kamal"
    version_tag = Time.current.to_i.to_s

    # Write :running immediately so the UI reflects the state on the
    # next page render, before Solid Queue even picks up the job.
    Rails.cache.write(
      PerformDeployJob::STATUS_CACHE_KEY,
      {
        state:       :running,
        target:      target,
        version_tag: version_tag,
        started_at:  Time.current,
        log:         ""
      },
      expires_in: PerformDeployJob::STATUS_TTL
    )

    # admin_user_id flows to the deploy job so it can package the current
    # admin's credentials into the Fly ROE_BOOTSTRAP secret. The production
    # initializer reads it on first boot to seed the admin user + Site
    # Sync token, so the operator can log in to the production admin
    # immediately after deploy without SSH.
    #
    # Sourced from Current.session.user_id — Authentication#resume_session
    # populates Current.session but not Current.user, so Current.user is
    # always nil here.
    PerformDeployJob.perform_later(
      target: target,
      version_tag: version_tag,
      admin_user_id: Current.session&.user_id
    )

    flash[:notice] = "Deploy started. This may take several minutes — the log updates as it runs."
    redirect_to admin_updates_path
  end

  # Same flow as start_deploy but with reset_cache: true so the job
  # prunes the remote build cache (Kamal SSH prune / Fly --no-cache)
  # before invoking the deploy command. Exposed as a separate action
  # so the failed-state UI has a distinct button — users intent
  # "retry, but force a clean build" rather than "deploy normally."
  def reset_and_retry_deploy
    if Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)&.dig(:state) == :running
      flash[:alert] = "A deploy is already in progress. Wait for it to finish."
      redirect_to admin_updates_path
      return
    end

    config = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    issues = deploy_prerequisites(config)

    if issues.any?
      flash[:alert] = "Deploy is not ready: #{issues.to_sentence}."
      redirect_to admin_updates_path
      return
    end

    target      = config["target"].presence || "kamal"
    version_tag = Time.current.to_i.to_s

    Rails.cache.write(
      PerformDeployJob::STATUS_CACHE_KEY,
      {
        state:       :running,
        target:      target,
        version_tag: version_tag,
        started_at:  Time.current,
        log:         "Clearing build cache before retry…\n"
      },
      expires_in: PerformDeployJob::STATUS_TTL
    )

    PerformDeployJob.perform_later(
      target: target,
      version_tag: version_tag,
      admin_user_id: Current.session&.user_id,
      reset_cache: true
    )

    flash[:notice] = "Cache reset + retry started. Expect a few extra minutes for the first build."
    redirect_to admin_updates_path
  end

  def deploy_status
    status = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    render json: (status || { state: nil })
  end

  def dismiss_deploy
    # Clear the in-progress/failed status from cache but preserve completed state
    # The LAST_DEPLOY_FILE keeps the timestamp for display after dismissal
    current_status = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    if current_status && current_status[:state] == :completed
      # Keep completed status but mark as dismissed (no longer showing success banner)
      Rails.cache.write(
        PerformDeployJob::STATUS_CACHE_KEY,
        current_status.merge(dismissed: true),
        expires_in: PerformDeployJob::STATUS_TTL
      )
    else
      # For running/failed states, just delete from cache
      Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY)
    end
    redirect_to admin_updates_path
  end

  def git_status
    unless system("which git > /dev/null 2>&1")
      return render json: { clean: true, git_unavailable: true, changed: [], count: 0 }
    end

    # Use Open3 with an array so spaces in Rails.root don't break the shell command.
    require "open3"
    output, = Open3.capture2("git", "-C", Rails.root.to_s, "status", "--porcelain")
    lines = output.strip.split("\n").reject(&:empty?)

    changed = lines.map do |line|
      code     = line[0..1].strip
      filename = line[3..].to_s.strip
      label    = case code
      when /^M/  then "modified"
      when /^A/  then "added"
      when /^D/  then "deleted"
      when /^R/  then "renamed"
      when /^\?/ then "untracked"
      else            "changed"
      end
      "#{label}: #{filename}"
    end

    render json: { clean: lines.empty?, changed: changed.first(10), count: lines.size }
  end

  # Flip site.yml's update_channel between "stable" and "nightly".
  # Read+write site.yml directly so we don't need to round-trip the
  # whole config through the bigger site-config editor flow. Clears
  # the version-check cache so the next page render reflects the
  # change immediately instead of waiting for the hourly recheck.
  def update_channel
    new_channel = params[:channel].to_s
    unless %w[stable nightly].include?(new_channel)
      redirect_to admin_updates_path, alert: "Unknown channel: #{new_channel}" and return
    end

    site_path = SiteConfig::SITE_FILE
    config = File.exist?(site_path) ? (YAML.load_file(site_path) || {}) : {}
    config["update_channel"] = new_channel
    File.write(site_path, YAML.dump(config))
    SiteConfig.sync_from_file("site")
    RoeUpdater::VersionChecker.clear_cache

    flash[:notice] = "Update channel set to #{new_channel}."
    redirect_to admin_updates_path
  end

  private

  # In production (the live deployed site), the entire Updates & Deploy
  # surface is irrelevant — updates and deploys originate from the user's
  # local Roe install. Redirect anyone landing here on a typed URL or
  # stale bookmark back to the dashboard, with a flash explaining where
  # to go. Status: :see_other so the redirect works for POST routes
  # (Deploy / Dismiss / Reset-and-retry) as well as GET ones, in case
  # the user triggers a form submission.
  def block_in_production
    return unless Rails.env.production?
    redirect_to admin_root_path,
                alert: "Updates and deploys happen from your local Roe install, not from the live site. Open your local admin's Updates & Deploy page instead.",
                status: :see_other
  end

  # Prevent the in-app updater from running on a developer checkout of
  # Roe itself. A dev install has HEAD on a named branch (e.g. `main`)
  # rather than detached at a release tag. Running the updater here
  # would clone a tagged release over an active development tree.
  # Hard-block the in-app updater on a developer checkout of Roe — HEAD on a
  # named git branch rather than a detached release tag. The updater clones
  # a tagged release over current/, which would destroy an active working
  # tree (this is exactly how a maintainer once lost uncommitted work: the
  # old "Test nightly" path passed prerelease=true to slip past this guard —
  # that escape hatch has been removed). A normal user install is a detached
  # tag, so it sails through and updates normally. Deploys are NOT blocked
  # here — those legitimately run from the local/dev install.
  def block_on_dev_install
    return unless RoeUpdater::VersionChecker.dev_install?
    redirect_to admin_updates_path,
                alert: "Updates are disabled on a development checkout of Roe. The in-app updater clones a release over current/, which would destroy your working tree — change versions with git instead.",
                status: :see_other
  end

  def license_valid?
    true
  end

  # Human-readable server/app descriptor for the card header
  def deploy_server_description(config, target, default_app_name)
    if target == "kamal"
      servers = Array(config.dig("kamal", "servers")).reject(&:blank?)
      servers.first.presence || "(no server configured)"
    else
      config["app_name"].presence || default_app_name
    end
  end

  # Confirmation message shown before deploy
  def deploy_confirmation_message(target, server_desc, config, default_app_name)
    if target == "kamal"
      "Build and push a Docker image to #{server_desc}, then restart the container. " \
      "The site will be briefly unavailable."
    else
      app_name = config["app_name"].presence || default_app_name
      "Deploy to Fly.io (app: #{app_name})."
    end
  end

  # Returns an array of human-readable strings describing unmet
  # prerequisites. An empty array means the deploy is ready to run.
  def deploy_prerequisites(config)
    issues = []
    target = config["target"].presence || "kamal"

    # Site URL is required for all deploy targets
    issues << "site URL is not set — configure it in Admin → Site Settings" if SiteConfig.site_url.blank?

    case target
    when "kamal"
      servers = Array(config.dig("kamal", "servers")).map(&:to_s).reject(&:blank?)
      issues << "no server address is set"     if servers.empty?
      issues << "registry username is not set" if config.dig("kamal", "registry_username").blank?
      issues << "registry token not set — add it in Deploy Configuration" unless DeploySecrets.current.registry_password.present?
      issues << "master.key not found at site/system/secrets/ — run bin/setup to generate it" unless DeployConfigGenerator.master_key_present?
      issues << "Kamal CLI is not available (run bundle install in current/)" unless DeployConfigGenerator.kamal_cli_available?
    when "fly"
      issues << "Fly region is not set"  if config.dig("fly", "region").blank?
      issues << "Fly CLI is not installed" unless DeployConfigGenerator.fly_cli_available?
    end

    issues
  end

  def load_last_deploy_time
    file_path = PerformDeployJob::LAST_DEPLOY_FILE
    return nil unless File.exist?(file_path)

    # Tolerate legacy files written with symbol keys (older deploys ran
    # to_yaml on a symbol-keyed hash), so an existing .last_deploy.yml
    # still reads until the next deploy rewrites it with string keys.
    data = YAML.safe_load_file(file_path, permitted_classes: [ Symbol, Time, Date ])
    return nil unless data.is_a?(Hash)

    completed = data["completed_at"] || data[:completed_at]
    return nil unless completed

    completed.is_a?(Time) ? completed : Time.parse(completed.to_s)
  rescue => e
    Rails.logger.error "Error loading last deploy time: #{e.message}"
    nil
  end
end

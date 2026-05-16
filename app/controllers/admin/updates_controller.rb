class Admin::UpdatesController < Admin::BaseController
  def index
    @current_version = RoeUpdater::VersionChecker.current_version
    @update_info     = RoeUpdater::VersionChecker.check_for_updates
    @last_update     = UpdateStatus.order(created_at: :desc).first
    @in_progress     = UpdateStatus.where(status: 'in_progress').exists?

    # Deploy section
    @deploy_status       = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    @deploy_config       = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    @deploy_issues       = deploy_prerequisites(@deploy_config)
    @fly_cli_available   = DeployConfigGenerator.fly_cli_available?
    @kamal_cli_available = DeployConfigGenerator.kamal_cli_available?
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

    if UpdateStatus.where(status: 'in_progress').exists?
      flash[:alert] = "An update is already in progress. Please wait for it to complete."
      redirect_to admin_updates_path
      return
    end

    unless license_valid?
      flash[:alert] = "License expired. Please renew to update."
      redirect_to admin_updates_path
      return
    end

    PerformUpdateJob.perform_later(version: version)

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

    target      = config['target'].presence || 'kamal'
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

    PerformDeployJob.perform_later(target: target, version_tag: version_tag)

    flash[:notice] = "Deploy started. This may take several minutes — the log updates as it runs."
    redirect_to admin_updates_path
  end

  def deploy_status
    status = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    render json: (status || { state: nil })
  end

  def dismiss_deploy
    Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY)
    redirect_to admin_updates_path
  end

  def git_status
    unless system('which git > /dev/null 2>&1')
      return render json: { clean: true, git_unavailable: true, changed: [], count: 0 }
    end

    # Use Open3 with an array so spaces in Rails.root don't break the shell command.
    require 'open3'
    output, = Open3.capture2('git', '-C', Rails.root.to_s, 'status', '--porcelain')
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

  private

  def license_valid?
    true
  end

  # Returns an array of human-readable strings describing unmet
  # prerequisites. An empty array means the deploy is ready to run.
  def deploy_prerequisites(config)
    issues = []
    target = config['target'].presence || 'kamal'

    case target
    when 'kamal'
      servers = Array(config.dig('kamal', 'servers')).map(&:to_s).reject(&:blank?)
      issues << "no server address is set"     if servers.empty?
      issues << "registry username is not set" if config.dig('kamal', 'registry_username').blank?
      issues << "registry password not set — add it in Deploy Configuration" unless DeploySecrets.current.registry_password.present?
      issues << "master key not found at config/master.key" unless DeployConfigGenerator.master_key_present?
      issues << "Kamal CLI is not available (run bundle install in current/)" unless DeployConfigGenerator.kamal_cli_available?
    when 'fly'
      issues << "Fly region is not set"  if config.dig('fly', 'region').blank?
      issues << "Fly CLI is not installed" unless DeployConfigGenerator.fly_cli_available?
    end

    issues
  end
end

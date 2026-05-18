require 'open3'

# Runs `kamal deploy` or `fly deploy` in a background job, capturing
# streaming output and writing it to the Rails cache so the Updates &
# Deploy page can poll and display live progress.
#
# Cache key: PerformDeployJob::STATUS_CACHE_KEY
# Cache shape:
#   {
#     state:        :running | :completed | :failed,
#     target:       'kamal' | 'fly',
#     version_tag:  String,   # timestamp for kamal, empty for fly
#     started_at:   Time,
#     completed_at: Time | nil,
#     log:          String,   # cumulative stdout+stderr
#     error:        String | nil
#   }
class PerformDeployJob < ApplicationJob
  queue_as :default

  STATUS_CACHE_KEY = 'deploy:status'.freeze
  STATUS_TTL       = 24.hours
  LAST_DEPLOY_FILE = File.join(RoeSitePaths::SITE_PATH, 'system', 'global', '.last_deploy.yml')

  def perform(target:, version_tag:)
    # Kamal builds from git-tracked files only, so uncommitted changes are
    # silently excluded from the image. Auto-commit anything pending before
    # building so the deployed image always reflects the current state on disk.
    auto_commit if target == 'kamal'

    cmd = build_command(target, version_tag)
    Rails.logger.info "[PerformDeployJob] Starting #{target} deploy (version: #{version_tag})"
    run_with_streaming(cmd, target: target, version_tag: version_tag)
  end

  private

  # Commits any staged or unstaged changes so Kamal's build context is current.
  # Uses inline git config so it works even when git user isn't globally
  # configured on the machine. Non-fatal — if git isn't available or commit
  # fails for any reason, the deploy continues with whatever git has.
  def auto_commit
    Bundler.with_original_env do
      # Use Open3/array-form system so spaces in Rails.root don't break the shell.
      output, = Open3.capture2('git', '-C', Rails.root.to_s, 'status', '--porcelain')
      return if output.strip.empty?

      timestamp = Time.current.strftime('%Y-%m-%d %H:%M')
      system('git', '-C', Rails.root.to_s, 'add', '-A')
      system(
        'git',
        '-C', Rails.root.to_s,
        '-c', 'user.email=roe@deploy.local',
        '-c', 'user.name=Roe Deploy',
        'commit', '-m', "Deploy #{timestamp}"
      )
      Rails.logger.info "[PerformDeployJob] Auto-committed pending changes before deploy"
    end
  rescue => e
    Rails.logger.warn "[PerformDeployJob] Auto-commit failed (#{e.message}) — continuing with deploy"
  end

  def build_command(target, version_tag)
    case target
    when 'kamal'
      # --version bypasses git SHA versioning so the deploy always uses
      # the files on disk, no commit required.
      "bundle exec kamal deploy --version=#{version_tag}"
    when 'fly'
      "fly deploy"
    else
      raise ArgumentError, "Unknown deploy target: #{target.inspect}"
    end
  end

  def run_with_streaming(cmd, target:, version_tag:)
    log         = ""
    last_write  = Time.current
    success     = false

    begin
      Bundler.with_original_env do
        Open3.popen2e(cmd, chdir: Rails.root.to_s) do |stdin, stdout_err, wait_thr|
          stdin.close

          stdout_err.each_line do |line|
            log += line

            # Throttle cache writes — once per second is plenty for the
            # polling interval (2 s) and avoids hammering the cache store.
            if Time.current - last_write >= 1.0
              write_status(state: :running, target: target, version_tag: version_tag, log: log)
              last_write = Time.current
            end
          end

          success = wait_thr.value.success?
        end
      end
    rescue => e
      Rails.logger.error "[PerformDeployJob] #{e.class}: #{e.message}"
      write_status(
        state:        :failed,
        target:       target,
        version_tag:  version_tag,
        log:          log + "\n[error] #{e.message}",
        completed_at: Time.current,
        error:        e.message
      )
      raise
    end

    if success
      completed_time = Time.current
      write_status(
        state:        :completed,
        target:       target,
        version_tag:  version_tag,
        log:          log,
        completed_at: completed_time,
        error:        nil
      )
      # Persist last deploy timestamp so it survives cache dismissal
      File.write(LAST_DEPLOY_FILE, { completed_at: completed_time.iso8601, target: target }.to_yaml)
      Rails.logger.info "[PerformDeployJob] #{target} deploy completed successfully"
    else
      write_status(
        state:        :failed,
        target:       target,
        version_tag:  version_tag,
        log:          log,
        completed_at: Time.current,
        error:        "Deploy command exited with a non-zero status. See log for details."
      )
      Rails.logger.error "[PerformDeployJob] #{target} deploy failed"
    end
  end

  def write_status(attrs)
    current = Rails.cache.read(STATUS_CACHE_KEY) || {}
    Rails.cache.write(STATUS_CACHE_KEY, current.merge(attrs), expires_in: STATUS_TTL)
  end
end

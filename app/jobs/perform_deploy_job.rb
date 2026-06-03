require "open3"

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

  STATUS_CACHE_KEY = "deploy:status".freeze
  STATUS_TTL       = 24.hours
  LAST_DEPLOY_FILE = File.join(RoeSitePaths::SITE_PATH, "system", "global", ".last_deploy.yml")

  def perform(target:, version_tag:, admin_user_id: nil)
    # Kamal builds from git-tracked files only, so uncommitted changes are
    # silently excluded from the image. Auto-commit anything pending before
    # building so the deployed image always reflects the current state on disk.
    auto_commit if target == "kamal"

    # Copy VERSION from root to current/ so Docker can access it during build
    prepare_version_file

    # Fly's release_command runs in an ephemeral VM that can't see the
    # mounted volume, so Roe doesn't use it for migrations. But the app
    # itself still needs RAILS_MASTER_KEY available as an env var to
    # decrypt credentials.yml.enc on boot. Sync the local master.key to
    # Fly secrets before deploying so users don't have to drop to a
    # terminal for `fly secrets set`.
    if target == "fly"
      sync_fly_master_key
      # Bootstrap data — admin user + SyncConfig.token — packaged as a
      # one-time Fly secret. The production initializer reads it on boot
      # and applies it only when the corresponding records are absent,
      # so re-deploys are no-ops.
      sync_fly_bootstrap_data(admin_user_id: admin_user_id) if admin_user_id.present?
    elsif target == "kamal"
      # Kamal analog: rewrite the ROE_BOOTSTRAP line in .kamal/secrets
      # with current admin + sync_token before kamal builds the image.
      # The default '{}' value from DeployConfigGenerator stays in place
      # when there's no admin to package (the prod initializer no-ops on
      # an empty payload).
      sync_kamal_bootstrap_data(admin_user_id: admin_user_id) if admin_user_id.present?
    end

    cmd = build_command(target, version_tag)
    Rails.logger.info "[PerformDeployJob] Starting #{target} deploy (version: #{version_tag})"
    run_with_streaming(cmd, target: target, version_tag: version_tag)
  ensure
    # Clean up temporary VERSION file
    cleanup_version_file
  end

  private

  # Commits any staged or unstaged changes so Kamal's build context is current.
  # Uses inline git config so it works even when git user isn't globally
  # configured on the machine. Non-fatal — if git isn't available or commit
  # fails for any reason, the deploy continues with whatever git has.
  def auto_commit
    Bundler.with_original_env do
      # Use Open3/array-form system so spaces in Rails.root don't break the shell.
      output, = Open3.capture2("git", "-C", Rails.root.to_s, "status", "--porcelain")
      return if output.strip.empty?

      timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
      system("git", "-C", Rails.root.to_s, "add", "-A")
      system(
        "git",
        "-C", Rails.root.to_s,
        "-c", "user.email=roe@deploy.local",
        "-c", "user.name=Roe Deploy",
        "commit", "-m", "Deploy #{timestamp}"
      )
      Rails.logger.info "[PerformDeployJob] Auto-committed pending changes before deploy"
    end
  rescue => e
    Rails.logger.warn "[PerformDeployJob] Auto-commit failed (#{e.message}) — continuing with deploy"
  end

  def prepare_version_file
    version_source = File.join(RoeSitePaths::ROE_ROOT, "VERSION")
    version_dest = File.join(Rails.root, "VERSION")

    if File.exist?(version_source)
      FileUtils.cp(version_source, version_dest)
      Rails.logger.info "[PerformDeployJob] Copied VERSION file for build context"
    else
      Rails.logger.warn "[PerformDeployJob] No VERSION file found at #{version_source}"
    end
  end

  def cleanup_version_file
    version_file = File.join(Rails.root, "VERSION")
    FileUtils.rm_f(version_file)
    Rails.logger.info "[PerformDeployJob] Cleaned up temporary VERSION file"
  end

  # Sync the local config/master.key to Fly's encrypted secret store
  # as RAILS_MASTER_KEY. Idempotent — only sets the secret when it
  # isn't already present on the Fly app. Uses --stage so the secret
  # is applied together with the next `fly deploy` instead of
  # triggering a separate machine restart.
  #
  # Failure modes surfaced to the deploy log:
  #   - No local config/master.key file → skip with warning
  #   - fly CLI not authenticated      → raise with "fly auth login" hint
  #   - fly secrets set failed         → raise with the CLI's stderr
  def sync_fly_master_key
    master_key_path = Rails.root.join("config", "master.key")
    unless File.exist?(master_key_path)
      Rails.logger.warn "[PerformDeployJob] No config/master.key found — skipping Fly secret sync. Deploy will likely fail at boot with 'Missing secret_key_base'."
      return
    end

    master_key = File.read(master_key_path).strip
    return if master_key.empty?

    Bundler.with_original_env do
      # Check what's already on the Fly app. The fly CLI picks up the
      # app name from fly.toml in the working directory, so chdir to
      # Rails.root where the generated fly.toml lives.
      list_out, list_err, list_status = Open3.capture3(
        "fly", "secrets", "list", chdir: Rails.root.to_s
      )

      unless list_status.success?
        # Most common cause is `fly auth login` hasn't been run. Surface
        # that to the deploy log so the operator knows what to do.
        if list_err =~ /auth|login|authoriz|token/i
          raise "Fly authentication is not set up on this machine. Run `fly auth login` from a terminal once, then retry the deploy. (fly secrets list said: #{list_err.strip})"
        end
        raise "Could not list Fly secrets: #{list_err.strip.presence || list_out.strip}"
      end

      if list_out.include?("RAILS_MASTER_KEY")
        Rails.logger.info "[PerformDeployJob] RAILS_MASTER_KEY already set on Fly — skipping sync"
        return
      end

      Rails.logger.info "[PerformDeployJob] Setting RAILS_MASTER_KEY on Fly (staged for next deploy)"
      set_out, set_err, set_status = Open3.capture3(
        "fly", "secrets", "set", "--stage", "RAILS_MASTER_KEY=#{master_key}",
        chdir: Rails.root.to_s
      )

      unless set_status.success?
        raise "Failed to set RAILS_MASTER_KEY on Fly: #{set_err.strip.presence || set_out.strip}"
      end
    end
  end

  # Build the JSON payload shipped in the ROE_BOOTSTRAP env var. Shared
  # between Fly (staged via `fly secrets set`) and Kamal (written into
  # `.kamal/secrets`). The production-side initializer
  # (config/initializers/roe_bootstrap.rb) decides per-section how to
  # apply each piece (admin: first-time only; sync_token + recovery
  # codes: always overwrite to match local).
  def build_bootstrap_payload(admin)
    sync_token = SyncConfig.current.token rescue nil
    recovery_code_digests = admin.recovery_codes.order(:id).map do |rc|
      { digest: rc.code_digest, consumed_at: rc.consumed_at&.iso8601 }.compact
    end

    {
      admin: {
        email_address:   admin.email_address,
        password_digest: admin.password_digest
      },
      sync_token:     sync_token,
      recovery_codes: recovery_code_digests.presence
    }.compact
  end

  # Bootstrap the production instance with admin credentials + Site Sync
  # token + recovery code digests, packaged as a single Fly secret
  # called ROE_BOOTSTRAP. The production-side initializer reads it on
  # boot and:
  #   - creates the admin user only when no users exist (idempotent —
  #     password rotations on prod won't get clobbered by redeploys)
  #   - always syncs SyncConfig.token to match (local is source of truth
  #     for the shared token; every deploy refreshes it)
  #   - replaces the admin's recovery_codes set wholesale (same "local
  #     is canonical" model — regenerating locally invalidates prod's
  #     old set on the next deploy)
  #
  # We push a fresh ROE_BOOTSTRAP secret on every deploy so the sync
  # token and recovery codes always reflect current local state.
  def sync_fly_bootstrap_data(admin_user_id:)
    admin = User.find_by(id: admin_user_id)
    unless admin
      Rails.logger.warn "[PerformDeployJob] No admin User found for id=#{admin_user_id.inspect} — skipping bootstrap sync"
      return
    end

    payload = build_bootstrap_payload(admin)

    Bundler.with_original_env do
      Rails.logger.info "[PerformDeployJob] Staging ROE_BOOTSTRAP on Fly (admin + sync token)"
      set_out, set_err, set_status = Open3.capture3(
        "fly", "secrets", "set", "--stage", "ROE_BOOTSTRAP=#{JSON.generate(payload)}",
        chdir: Rails.root.to_s
      )

      unless set_status.success?
        Rails.logger.warn "[PerformDeployJob] Failed to set ROE_BOOTSTRAP on Fly: #{set_err.strip.presence || set_out.strip}"
      end
    end
  end

  # Kamal analog of sync_fly_bootstrap_data. Builds the same admin +
  # sync_token payload and rewrites the ROE_BOOTSTRAP line in
  # .kamal/secrets in place. DeployConfigGenerator.generate_secrets!
  # seeds that line with '{}' so kamal can always satisfy the
  # env.secret entry; this method just upgrades it to the real payload
  # when an admin is known.
  #
  # Idempotent: every deploy rewrites with current state, so a rotated
  # admin password or fresh sync_token propagates on the next deploy
  # without manual file editing.
  def sync_kamal_bootstrap_data(admin_user_id:)
    admin = User.find_by(id: admin_user_id)
    unless admin
      Rails.logger.warn "[PerformDeployJob] No admin User found for id=#{admin_user_id.inspect} — skipping Kamal bootstrap sync"
      return
    end

    secrets_path = Rails.root.join(".kamal", "secrets")
    unless File.exist?(secrets_path)
      Rails.logger.warn "[PerformDeployJob] .kamal/secrets not found — skipping ROE_BOOTSTRAP write (run Deploy Config save first to generate it)"
      return
    end

    payload = build_bootstrap_payload(admin)

    # Single-quoted so the JSON's double quotes pass through Kamal's
    # dotenv parser unchanged. The payload's values (bcrypt hash, hex
    # token, email) never contain single quotes in practice, so no
    # internal escaping is needed.
    new_line = "ROE_BOOTSTRAP='#{JSON.generate(payload)}'"

    content = File.read(secrets_path)
    if content.lines.any? { |l| l.start_with?("ROE_BOOTSTRAP=") }
      content = content.lines.map { |l| l.start_with?("ROE_BOOTSTRAP=") ? "#{new_line}\n" : l }.join
    else
      content += "\n" unless content.end_with?("\n")
      content += "#{new_line}\n"
    end

    File.write(secrets_path, content)
    Rails.logger.info "[PerformDeployJob] Wrote ROE_BOOTSTRAP to .kamal/secrets (admin: #{admin.email_address})"
  end

  def build_command(target, version_tag)
    case target
    when "kamal"
      # --version bypasses git SHA versioning so the deploy always uses
      # the files on disk, no commit required.
      "bundle exec kamal deploy --version=#{version_tag}"
    when "fly"
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

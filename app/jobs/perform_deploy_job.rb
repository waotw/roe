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

  # A deploy that goes quiet for this long is treated as hung and stopped.
  #
  # Deliberately generous. DeployWatchdog declines to guess "stuck" from log
  # silence for good reason — a quiet `docker build` layer can run for minutes
  # — and killing a working deploy is far worse than letting a dead one sit.
  # This isn't that guess: nothing here infers a stall mid-deploy and reports
  # it, it only stops a command that has produced nothing at all for ten
  # minutes, which no real build stage does.
  STALL_TIMEOUT = 10.minutes

  # How often to look up from the read while it's quiet.
  STALL_POLL = 1

  # How long a stalled command gets to exit on TERM before it's KILLed. A wedged
  # CLI often ignores TERM; a healthy one uses this to clean up after itself.
  TERM_GRACE = 2

  # Written into both the log and the error so DeployDiagnostics can recognise
  # a stall. It has to be a marker we plant: every other signature matches text
  # the failing command printed, and a stall is defined by printing nothing.
  STALL_MARKER = "roe: deploy stalled".freeze
  LAST_DEPLOY_FILE = File.join(RoeSitePaths::SITE_PATH, "system", "global", ".last_deploy.yml")

  def perform(target:, version_tag:, admin_user_id: nil, reset_cache: false)
    # Refuse to run a deploy nobody is waiting for.
    #
    # Solid Queue puts an in-flight job back on the queue when a worker shuts
    # down cleanly (Process::Executor#release_all_claimed_executions), so
    # quitting Roe mid-deploy can hand this job straight back for the next boot
    # to pick up. A deploy is not safe to resume unattended hours later: it
    # auto-commits the working tree, pushes secrets and builds an image, all
    # with nobody watching. Dropping it is the right default — the button is
    # still there.
    return unless claim_deploy!(version_tag)

    # Stage VERSION FIRST. Kamal builds from the git tree, not the raw
    # working directory — anything not committed is silently absent
    # from the build context. If we auto-commit BEFORE staging VERSION
    # (the way this method used to read), the file lands on disk as
    # an untracked file Kamal never sees, and the Dockerfile's
    # COPY --from=build /rails/VERSION fails downstream with the
    # cryptic "failed to compute cache key … /rails/VERSION: not found"
    # error. Staging first means the auto_commit below picks VERSION
    # up alongside any genuine user changes.
    prepare_version_file

    # Auto-commit any pending changes (now including the just-staged
    # VERSION). For Kamal this is required — Kamal builds from the
    # git tree, so uncommitted files are silently absent from the
    # build context. For Fly it's not required for the deploy itself
    # (Fly's builder ships the working directory directly), but the
    # user clicked "Auto-commit and deploy" in the UI expecting their
    # working tree to be in a clean state after deploy — running it
    # on the Fly path too honors that intent and keeps git history
    # aligned with what was deployed. auto_commit no-ops when
    # `git status --porcelain` is empty, so it's safe to run for
    # both targets unconditionally.
    auto_commit

    # Fly's release_command runs in an ephemeral VM that can't see the
    # mounted volume, so Roe doesn't use it for migrations. Multi-Machine
    # Fly apps also can't share /site/system/secrets/ across Machines
    # (each Machine has its own persistent volume), so Fly Machines
    # read their crypto material from env vars instead. Sync the local
    # install's secrets to the Fly secret store before deploying so
    # users don't have to drop to a terminal for `fly secrets set`.
    if target == "fly"
      sync_fly_secrets
      # Bootstrap data — admin user + SyncConfig.token — packaged as a
      # one-time Fly secret. The production initializer reads it on boot
      # and applies it only when the corresponding records are absent,
      # so re-deploys are no-ops.
      sync_fly_bootstrap_data(admin_user_id: admin_user_id) if admin_user_id.present?
    elsif target == "kamal"
      # Self-heal .kamal/secrets before anything reads it. It's gitignored
      # and written by DeployConfigGenerator (on Deploy Config save), so a
      # fresh checkout — e.g. after an in-app update re-clones current/ —
      # won't have it, and kamal aborts with
      #   Secret 'KAMAL_REGISTRY_PASSWORD' not found
      # Regenerate from the stored registry token + master.key so the
      # deploy just works instead of failing at the last step.
      ensure_kamal_secrets!

      # Cache reset before bootstrap + build. Prunes locally, because that's
      # where builds run. Failures are logged but don't abort — a flaky prune
      # shouldn't block a deploy the user explicitly asked to retry.
      clear_build_cache if reset_cache

      # Kamal analog: rewrite the ROE_BOOTSTRAP line in .kamal/secrets
      # with current admin + sync_token before kamal builds the image.
      # The default '{}' value from DeployConfigGenerator stays in place
      # when there's no admin to package (the prod initializer no-ops on
      # an empty payload).
      sync_kamal_bootstrap_data(admin_user_id: admin_user_id) if admin_user_id.present?
    end

    # Fail before the build, not four minutes into it.
    #
    # Kamal reports a missing local Docker as whatever it failed to reach next,
    # which reads as a problem with the server rather than this computer. Fly
    # is worse: with an expired session `fly deploy` produces no output and
    # never returns, so the page sits with an empty log and no way back. Both
    # are cheaper to catch here than to diagnose from a stuck screen.
    if (blockers = DeployPreflight.new.blockers(target)).any?
      Rails.logger.warn "[PerformDeployJob] Preflight failed: #{blockers.map(&:title).join('; ')}"
      write_status(
        state:        :failed,
        target:       target,
        version_tag:  version_tag,
        finished_at:  Time.current,
        log:          blockers.map { |b| "[preflight] #{b.title}" }.join("\n"),
        error:        blockers.map(&:title).join(". ") + ".",
        preflight:    blockers.map { |b| { title: b.title, explanation: b.explanation, steps: b.steps } }
      )
      return
    end

    cmd = build_command(target, version_tag, reset_cache: reset_cache)
    Rails.logger.info "[PerformDeployJob] Starting #{target} deploy (version: #{version_tag}#{reset_cache ? ', cache reset requested' : ''})"

    # When a cache reset was requested for Kamal, pass a fresh timestamp
    # via KAMAL_CACHE_BUST so the generated deploy.yml's
    # `args: CACHE_BUST: <%= ENV["KAMAL_CACHE_BUST"] || "stable" %>`
    # resolves to a never-seen value. That value flows into the Docker
    # build as a build-arg, which invalidates the cache point we put
    # just before `COPY . .` in the Dockerfile — forcing the build
    # context layer to be re-read from scratch instead of being pulled
    # back stale from --cache-from registry.
    extra_env = (reset_cache && target == "kamal") ? { "KAMAL_CACHE_BUST" => Time.current.to_i.to_s } : {}

    run_with_streaming(cmd, target: target, version_tag: version_tag, env: extra_env)
  end

  private

  # True when this job is the deploy the page is currently showing, and hasn't
  # already had a go.
  #
  # Three ways it can be false, all meaning "don't deploy":
  #
  #   no status      — dismissed, or the TTL passed. Nobody is watching.
  #   another tag    — a newer deploy superseded this one.
  #   already begun  — this job ran before and was re-queued by a restart.
  #
  # The last is the one that matters, and it's why this records the attempt
  # rather than just reading. Solid Queue doesn't count a released execution as
  # a retry, so `executions` stays 1 and can't tell a resumed job from a fresh
  # one. A marker in the status can.
  def claim_deploy!(version_tag)
    status = Rails.cache.read(STATUS_CACHE_KEY)

    reason =
      if status.nil?                                        then "no deploy status — it was dismissed or expired"
      elsif status[:version_tag].to_s != version_tag.to_s   then "superseded by a newer deploy"
      elsif status[:job_started_at].present?                then "already started once — Roe restarted while it was running"
      end

    if reason
      Rails.logger.warn "[PerformDeployJob] Skipping deploy #{version_tag}: #{reason}"
      return false
    end

    write_status(job_started_at: Time.current)
    true
  end

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

  # Pushes the local install's secret_key_base + AR encryption keys
  # to Fly's secret store so multi-Machine Fly apps share consistent
  # crypto material (same SECRET_KEY_BASE = same cookie signing,
  # same AR encryption keys = same column decryption). Delegates to
  # FlySecretsSync which handles the read-decrypt-list-set flow
  # idempotently — secrets already set on Fly are skipped, so this
  # is safe to run on every deploy.
  #
  # Replaces an earlier `sync_fly_master_key` that pushed
  # RAILS_MASTER_KEY from a now-defunct config/master.key location.
  # On Fly, credentials.yml.enc is no longer involved at all — the
  # config branch in config/application.rb feeds AR encryption keys
  # directly from env vars when FLY_APP_NAME is present.
  def sync_fly_secrets
    result = FlySecretsSync.run(logger: Rails.logger)

    if result.set_keys.any?
      Rails.logger.info "[PerformDeployJob] Staged Fly secrets: #{result.set_keys.join(', ')}"
    end
    if result.skipped_keys.any?
      Rails.logger.info "[PerformDeployJob] Fly secrets already set, skipped: #{result.skipped_keys.join(', ')}"
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

  # Ensure .kamal/secrets exists before kamal reads it. The file is
  # gitignored and generated by DeployConfigGenerator (on Deploy Config
  # save), so a fresh checkout won't have it. Generate it from the stored
  # registry token + master.key when missing; generate_secrets! raises a
  # clear error if the registry token isn't set (deploy_prerequisites
  # already blocks that case before the job runs).
  def ensure_kamal_secrets!
    return if File.exist?(Rails.root.join(".kamal", "secrets"))
    Rails.logger.info "[PerformDeployJob] .kamal/secrets missing — regenerating from stored config"
    DeployConfigGenerator.generate_secrets!
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

  def build_command(target, version_tag, reset_cache: false)
    case target
    when "kamal"
      # --version bypasses git SHA versioning so the deploy always uses
      # the files on disk, no commit required. Cache reset for Kamal
      # happens out-of-band via clear_build_cache (a local prune before
      # kamal runs); the command itself stays unchanged.
      "bundle exec kamal deploy --version=#{version_tag}"
    when "fly"
      # Fly's builder cache lives on their infrastructure, not on a
      # box we can SSH into. --no-cache is the equivalent escape
      # hatch — one build runs cold, subsequent builds rebuild the
      # cache normally.
      reset_cache ? "fly deploy --no-cache" : "fly deploy"
    else
      raise ArgumentError, "Unknown deploy target: #{target.inspect}"
    end
  end

  # Clear BuildKit + builder cache on the machine that does the building —
  # this one.
  #
  # This used to SSH into the deploy server and prune there, back when
  # deploy.yml configured a remote builder. That builder is gone (it pointed
  # at the same small droplet that serves the site), so the cache this needs
  # to clear is local. Pruning the server cleared a cache nothing was using
  # while leaving the real one untouched — the button did nothing.
  #
  # Best-effort: failures are logged but never raise. The whole point is to
  # recover from a stuck state and the user is retrying regardless, so a
  # failed prune shouldn't fail the retry on top of it.
  def clear_build_cache
    Rails.logger.info "[PerformDeployJob] Clearing local build cache"

    Bundler.with_original_env do
      output, status = Open3.capture2e(
        "docker", "buildx", "prune", "--force", "--all"
      )

      if status.success?
        Rails.logger.info "[PerformDeployJob] Local build cache cleared"
      else
        Rails.logger.warn "[PerformDeployJob] Cache clear failed: #{output.lines.first&.strip}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn "[PerformDeployJob] Cache clear failed: #{e.message}"
  end

  # Overridable so a test doesn't have to wait ten minutes to prove the timeout.
  def stall_timeout = STALL_TIMEOUT
  def term_grace    = TERM_GRACE

  # TERM the whole group, not just the child. `kamal deploy` and `fly deploy`
  # are front ends — the thing actually hung is usually a docker or ssh
  # grandchild, and killing the parent alone orphans it still holding the
  # resource. pgroup: true on spawn is what makes the negative pid work.
  def terminate_process_group(pid)
    Process.kill("TERM", -pid)
    sleep term_grace
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    # Already gone, or not ours to signal — either way there's nothing to stop.
  end

  def run_with_streaming(cmd, target:, version_tag:, env: {})
    log         = ""
    last_write  = Time.current
    success     = false
    stalled     = false

    begin
      Bundler.with_original_env do
        # Pass the explicit env hash as Open3's first arg so it merges
        # over the inherited ENV without us having to hand-roll the
        # subprocess setup. Empty hash is a no-op.
        # pgroup: true so the deploy and everything it spawns share a group we
        # can stop as one. Without it a stall timeout can only kill the front
        # end and leaves the wedged child running.
        Open3.popen2e(env, cmd, chdir: Rails.root.to_s, pgroup: true) do |stdin, stdout_err, wait_thr|
          stdin.close

          last_output = Time.current
          buffer      = +""

          # Read with a deadline rather than each_line, which blocks forever on
          # a command that never writes and never exits — the whole bug.
          loop do
            if stdout_err.wait_readable(STALL_POLL)
              begin
                buffer << stdout_err.readpartial(4096)
              rescue EOFError
                break
              end
              last_output = Time.current

              # readpartial lands on chunk boundaries, not line ones. Emit whole
              # lines and hold the remainder for the next read.
              while (newline = buffer.index("\n"))
                log += buffer.slice!(0..newline)
              end

              # Throttle cache writes — once per second is plenty for the
              # polling interval (2 s) and avoids hammering the cache store.
              if Time.current - last_write >= 1.0
                write_status(state: :running, target: target, version_tag: version_tag, log: log)
                last_write = Time.current
              end
            elsif Time.current - last_output >= stall_timeout
              stalled = true
              terminate_process_group(wait_thr.pid)
              break
            end
          end

          log += buffer # whatever it printed without a trailing newline
          # Short-circuit: after a kill there's no exit status worth reading,
          # and a stalled deploy failed whatever the process eventually says.
          success = !stalled && wait_thr.value.success?
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
      # Persist last deploy timestamp so it survives cache dismissal.
      # String keys (so load_last_deploy_time can read them back — symbol
      # keys don't survive the reader's safe-load), and drop to_yaml's
      # leading "---\n" document marker to keep the file clean.
      yaml = { "completed_at" => completed_time.iso8601, "target" => target.to_s }.to_yaml.delete_prefix("---\n")
      File.write(LAST_DEPLOY_FILE, yaml)
      Rails.logger.info "[PerformDeployJob] #{target} deploy completed successfully"
    else
      minutes = (stall_timeout / 60).round

      # The log is kept exactly as collected. On a stall it's the only evidence
      # there is, and it's usually where the deploy got to before going quiet.
      log += "\n[#{STALL_MARKER}] no output for #{minutes} minutes — Roe stopped the deploy.\n" if stalled

      write_status(
        state:        :failed,
        target:       target,
        version_tag:  version_tag,
        log:          log,
        completed_at: Time.current,
        error:        if stalled
          [ "The deploy stopped responding — no output for #{minutes} minutes, " \
            "so Roe stopped it (#{STALL_MARKER}).",
            # Stopping mid-deploy leaves the same residue as Roe quitting
            # mid-deploy, so it gets the same warning.
            DeployWatchdog.cleanup_hint(target) ].compact.join(" ")
        else
          "Deploy command exited with a non-zero status. See log for details."
        end
      )
      Rails.logger.error "[PerformDeployJob] #{target} deploy #{stalled ? 'stalled and was stopped' : 'failed'}"
    end
  end

  # Tracks how many times in a row a deploy has failed, which is what tells
  # the failure panel whether a cold build is worth offering. One failure is
  # usually something you go and fix; a second means the cheap retry isn't
  # working.
  #
  # Counted here rather than compared by content because every non-zero exit
  # writes the same error string — comparing those would call every failure a
  # repeat. The count carries through the :running state on a retry (merge
  # keeps it) and resets on success or dismissal.
  def write_status(attrs)
    current = Rails.cache.read(STATUS_CACHE_KEY) || {}

    attrs = case attrs[:state]
    when :failed    then attrs.merge(consecutive_failures: current[:consecutive_failures].to_i + 1)
    when :completed then attrs.merge(consecutive_failures: 0)
    else attrs
    end

    Rails.cache.write(STATUS_CACHE_KEY, current.merge(attrs), expires_in: STATUS_TTL)
  end
end

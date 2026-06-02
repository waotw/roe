# Generates platform-specific deployment config files from the abstract
# site/system/global/deploy.yml (the user-managed source of truth).
#
# Always generates BOTH files on each call so they stay in sync regardless
# of which target is currently active — switching targets and saving once
# is all that's needed.
#
# Output files:
#   config/deploy.yml  — Kamal deploy config (read by `kamal` CLI + KamalRsync)
#   fly.toml           — Fly.io app config   (read by `fly` CLI)
#
# Secrets are NEVER written here. The registry password lives in
# .kamal/secrets as KAMAL_REGISTRY_PASSWORD, and the Rails master key in
# the same file as RAILS_MASTER_KEY. Fly credentials come from
# `fly auth login` / FLY_API_TOKEN env var.
class DeployConfigGenerator
  class GenerationError < StandardError; end

  # ── Hardcoded Roe conventions ────────────────────────────────────────────
  # These are intentionally not user-configurable. Developers who need
  # to change them can edit config/deploy.yml or fly.toml directly.

  # Fly volume source — created by Roe's provisioning scripts.
  FLY_VOLUME_SOURCE = "data".freeze

  # Docker registry — docker.io covers the vast majority of Roe users.
  # Anyone using GHCR or a private registry edits config/deploy.yml directly.
  KAMAL_REGISTRY_SERVER = "docker.io".freeze

  # Host filesystem path where /site lives on the Kamal server.
  # Must stay stable — SiteSync::KamalRsync rsyncs here.
  KAMAL_HOST_VOLUME_PATH = "/var/lib/roe/site".freeze

  # Container-side mount point — matches KamalRsync::REMOTE_SITE_CONTAINER_PATH.
  CONTAINER_MOUNT_PATH = "/data/site".freeze

  # SQLite requires single-container deploys; 1 CPU is the right default.
  FLY_VM_CPUS = 1

  def self.generate!
    new.generate!
  end

  # Writes .kamal/secrets from the stored DeploySecrets registry password
  # and the Rails master key at config/master.key.
  # Raises GenerationError with a clear message if either is missing.
  def self.generate_secrets!
    master_key_path = Rails.root.join("config", "master.key")

    raise GenerationError, "config/master.key not found — this file must exist to deploy" unless File.exist?(master_key_path)

    master_key = File.read(master_key_path).strip
    raise GenerationError, "config/master.key is empty" if master_key.blank?

    secrets = DeploySecrets.current
    raise GenerationError, "Registry password not set — add it in Deploy Configuration" unless secrets.registry_password.present?

    secrets_path = Rails.root.join(".kamal", "secrets")
    FileUtils.mkdir_p(File.dirname(secrets_path))

    File.write(secrets_path, <<~SECRETS)
      KAMAL_REGISTRY_PASSWORD=#{secrets.registry_password}
      RAILS_MASTER_KEY=#{master_key}
    SECRETS

    { file: ".kamal/secrets" }
  rescue GenerationError
    raise
  rescue => e
    raise GenerationError, "Failed to write .kamal/secrets: #{e.message}"
  end

  # Returns true if config/master.key exists and has content.
  def self.master_key_present?
    path = Rails.root.join("config", "master.key")
    File.exist?(path) && File.read(path).strip.present?
  rescue
    false
  end

  # Returns true if the `fly` CLI is available in PATH.
  # Used by the deploy config form and the future Updates & Deploy page
  # to show installation guidance before the user tries to deploy.
  def self.fly_cli_available?
    system("which fly > /dev/null 2>&1")
  end

  # Returns true if `bundle exec kamal` is available.
  # Kamal is in the Gemfile so this should always be true in a
  # properly set-up Roe install, but worth checking defensively.
  def self.kamal_cli_available?
    system("bundle exec kamal version > /dev/null 2>&1")
  end

  # Returns an array of { file:, target: } hashes for each file written,
  # e.g. [{ file: 'config/deploy.yml', target: :kamal }, { file: 'fly.toml', target: :fly }]
  def generate!
    config = load_config
    [
      write_kamal_config(config),
      write_fly_toml(config)
    ]
  end

  private

  def load_config
    unless File.exist?(SiteConfig::DEPLOY_FILE)
      raise GenerationError, "deploy.yml not found at #{SiteConfig::DEPLOY_FILE}"
    end

    YAML.load_file(SiteConfig::DEPLOY_FILE) || {}
  rescue Psych::SyntaxError => e
    raise GenerationError, "deploy.yml has invalid YAML: #{e.message}"
  end

  # ── Paths ────────────────────────────────────────────────────────────────

  def kamal_dest
    Rails.root.join("config", "deploy.yml")
  end

  def fly_dest
    Rails.root.join("fly.toml")
  end

  # ── Kamal config/deploy.yml ──────────────────────────────────────────────

  def write_kamal_config(config)
    FileUtils.mkdir_p(File.dirname(kamal_dest))
    File.write(kamal_dest, kamal_content(config))
    { file: "config/deploy.yml", target: :kamal }
  rescue GenerationError
    raise
  rescue => e
    raise GenerationError, "Failed to write config/deploy.yml: #{e.message}"
  end

  def kamal_content(config)
    default_app_name = File.basename(RoeSitePaths::ROE_ROOT).presence || "roe"
    app_name     = config["app_name"].presence || default_app_name
    reg_username = config.dig("kamal", "registry_username").to_s.strip
    image_name   = config.dig("kamal", "image_name").presence || app_name
    servers      = Array(config.dig("kamal", "servers")).map(&:to_s).reject(&:blank?)
    ssl          = config["ssl"] != false
    first_server = servers.first.presence || "YOUR_SERVER_IP"
    image        = reg_username.present? ? "#{reg_username}/#{image_name}" : image_name

    servers_yaml = if servers.any?
      servers.map { |s| "    - #{s}" }.join("\n")
    else
      "    - YOUR_SERVER_IP"
    end

    # SSL requires a custom domain — always generated as a commented
    # reference block. When the user is ready to enable SSL:
    #   1. Point their domain's A record at the server
    #   2. Uncomment and fill in the proxy block below
    #   3. Run: kamal proxy reboot
    ssl_value    = ssl ? "true" : "false"
    proxy_block  = "# To enable SSL with a custom domain:\n" \
                   "# 1. Point your domain's A record at the server\n" \
                   "# 2. Uncomment the proxy block below and set your domain\n" \
                   "# 3. Run: kamal proxy reboot\n" \
                   "#\n" \
                   "# proxy:\n" \
                   "#   ssl: #{ssl_value}\n" \
                   "#   host: your-domain.com"

    <<~YAML
      # Kamal deployment config for Roe.
      # Generated from site/system/global/deploy.yml — edit via Admin → Configuration → deploy.yml.
      #
      # Sensitive values live in .kamal/secrets (gitignored). The volume mapping
      # for #{CONTAINER_MOUNT_PATH} is used by SiteSync::KamalRsync — keep that path stable.

      service: #{app_name}
      image: #{image}

      servers:
        web:
      #{servers_yaml}

      #{proxy_block}

      registry:
        server: #{KAMAL_REGISTRY_SERVER}
        username: #{reg_username.presence || 'YOUR_REGISTRY_USERNAME'}
        password:
          - KAMAL_REGISTRY_PASSWORD

      env:
        secret:
          - RAILS_MASTER_KEY
        clear:
          SOLID_QUEUE_IN_PUMA: true

      volumes:
        - "roe_storage:/rails/storage"
        - "#{KAMAL_HOST_VOLUME_PATH}:#{CONTAINER_MOUNT_PATH}"

      asset_path: /rails/current/public/assets

      builder:
        arch: amd64
        remote: ssh://root@#{first_server}

      boot:
        limit: 1
        wait: 0

      aliases:
        console: app exec --interactive --reuse "bin/rails console"
        shell: app exec --interactive --reuse "bash"
        logs: app logs -f
        dbc: app exec --interactive --reuse "bin/rails dbconsole --include-password"
    YAML
  end

  # ── Fly fly.toml ─────────────────────────────────────────────────────────

  def write_fly_toml(config)
    FileUtils.mkdir_p(File.dirname(fly_dest))
    File.write(fly_dest, fly_content(config))
    { file: "fly.toml", target: :fly }
  rescue GenerationError
    raise
  rescue => e
    raise GenerationError, "Failed to write fly.toml: #{e.message}"
  end

  def fly_content(config)
    default_app_name = File.basename(RoeSitePaths::ROE_ROOT).presence || "roe"
    app_name  = config["app_name"].presence || default_app_name
    region    = config.dig("fly", "region").to_s.strip.presence || "iad"
    vm_memory = config.dig("fly", "vm_memory").presence || "1gb"
    ssl       = config["ssl"] != false

    vol_dest  = File.dirname(CONTAINER_MOUNT_PATH)
    memory_mb = parse_memory_mb(vm_memory)

    <<~TOML
      # fly.toml — generated by Roe from site/system/global/deploy.yml
      # Edit via Admin → Configuration → deploy.yml, then save to regenerate.
      #
      # See https://fly.io/docs/reference/configuration/ for reference.

      app = '#{app_name}'
      primary_region = '#{region}'
      console_command = '/rails/current/bin/rails console'

      [build]

      [env]
        PORT = '8080'
        SOLID_QUEUE_IN_PUMA = 'true'

      # No [deploy] release_command. Fly runs release_command in an
      # ephemeral VM that does NOT have the persistent volume mounted,
      # so SQLite migrations there either crash ("no such table") or
      # silently create a throwaway DB that gets discarded.
      # bin/docker-entrypoint runs `bin/rails db:prepare` on each app
      # machine start, after the volume is mounted — which is where
      # migrations belong for a file-backed-DB app like Roe.

      [processes]
        app = '/rails/current/bin/rails server -b 0.0.0.0 -p 8080'

      [[mounts]]
        source = '#{FLY_VOLUME_SOURCE}'
        destination = '#{vol_dest}'

      [http_service]
        internal_port = 8080
        force_https = #{ssl}
        auto_stop_machines = false
        auto_start_machines = true
        min_machines_running = 1
        processes = ['app']

        [[http_service.checks]]
          interval = '10s'
          timeout = '5s'
          grace_period = '30s'
          method = 'GET'
          path = '/up'
          protocol = 'http'
          tls_skip_verify = false

          [http_service.checks.headers]
            X-Forwarded-Proto = 'https'

      [[vm]]
        memory = '#{vm_memory}'
        cpus = #{FLY_VM_CPUS}
        memory_mb = #{memory_mb}
    TOML
  end

  # Converts a human memory string to megabytes for Fly's memory_mb field.
  # Accepts "1gb", "512mb", bare integers (assumed MB), etc.
  def parse_memory_mb(memory_str)
    case memory_str.to_s.downcase.strip
    when /^(\d+)\s*gb$/
      Regexp.last_match(1).to_i * 1024
    when /^(\d+)\s*mb$/
      Regexp.last_match(1).to_i
    when /^(\d+)$/
      Regexp.last_match(1).to_i
    else
      1024 # safe fallback for 1 GB
    end
  end
end

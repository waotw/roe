require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Allow additional hosts from development config (e.g., ngrok for testing webhooks).
  # Uses |= so repeated evaluations (Rails autoreload) don't accumulate duplicates,
  # which causes Rails 8's HostAuthorization middleware to misfire.
  _dev_config_path = File.join(RoeSitePaths::SITE_PATH, "system", "global", "development.yml")
  if File.exist?(_dev_config_path)
    dev_config = YAML.load_file(_dev_config_path)
    allowed_hosts = Array(dev_config&.dig("allowed_hosts")).map(&:to_s).select(&:present?)
    config.hosts |= allowed_hosts unless allowed_hosts.empty?
  end

  # Registered installs are reached at <name>.roe (see roe.sh
  # register). Allow the whole suffix so every registered site passes Host
  # Authorization without each one editing development.yml.
  #
  # No \A or \z here: HostAuthorization wraps each regexp as
  # /\A<regexp>(:\d+)?\z/ so the port is allowed. Our own \z would sit
  # before the optional port and reject every "name.roe:3001" Host header.
  config.hosts |= [ /[a-z0-9-]+\.roe/ ]

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :solid_cache_store, {
    database: :cache  # Tell it to use the cache database
  }

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Make template changes take effect pimmediately.
  config.action_mailer.perform_caching = false

  # Set localhost to be used by links generated in mailer templates.
  config.action_mailer.delivery_method = :letter_opener
  config.action_mailer.perform_deliveries = true
  # Mailer links must point at THIS install. Member sign-in is magic-link
  # based, so a wrong host or port sends someone to a different site's login
  # once more than one install runs locally — a real breakage, not cosmetic.
  #
  # Read site.yml directly rather than through SiteConfig: this runs during
  # boot, before the database is connected and before autoloading app code
  # is safe. Host prefers ROE_HOST (set by roe.sh for a registered install,
  # its <name>.roe hostname), then site.yml; port prefers the port the
  # server actually bound (roe.sh exports PORT) and falls back to site.yml's.
  config.action_mailer.default_url_options = begin
    site_yml = File.join(RoeSitePaths::SITE_SYSTEM_PATH, "global", "site.yml")
    raw      = File.exist?(site_yml) ? YAML.safe_load_file(site_yml, aliases: true) : nil
    bare     = (raw.is_a?(Hash) ? raw["url"].to_s : "").sub(%r{\Ahttps?://}, "").sub(%r{/.*\z}, "")
    host, _, configured_port = bare.partition(":")
    host = ENV["ROE_HOST"] if ENV["ROE_HOST"].present?

    port = if ENV["PORT"].to_i.positive?
      ENV["PORT"].to_i
    elsif configured_port.present?
      configured_port.to_i
    else
      3000
    end

    { host: host.presence || "localhost", port: port }
  rescue StandardError => e
    warn "[Roe] couldn't read site.yml for mailer URLs (#{e.class}: #{e.message}); using localhost"
    { host: "localhost", port: 3000 }
  end

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # add solid_queue connection
  config.active_job.queue_adapter = :solid_queue
  config.after_initialize do
    SolidQueue.connects_to = { database: { writing: :queue, reading: :queue } }
  end

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Apply autocorrection by RuboCop to files generated by `bin/rails generate`.
  # config.generators.apply_rubocop_autocorrect_after_generate!

  config.public_file_server.enabled = false
end

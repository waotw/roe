# Maintainer-only Fly utilities.
#
# The Admin → Deploy flow auto-syncs Fly secrets via PerformDeployJob
# on every Fly deploy (idempotent — secrets already on Fly are skipped),
# so most users never need to invoke this rake task. It exists for
# two manual cases:
#
#   1. Rotating secrets on a Fly app — pass FORCE=1 to overwrite
#      values that are already set. This invalidates existing
#      sessions and orphans AR-encrypted column data, so don't run
#      it casually.
#
#   2. Diagnostic / dry-run before a deploy — running without FORCE
#      shows which secrets are present vs. missing on the target
#      Fly app without ever rotating them.
#
# Both flows delegate to the same FlySecretsSync service the deploy
# job uses, so behaviour is identical to the Admin deploy path.

namespace :roe do
  namespace :fly do
    desc "Push local secrets to Fly secret store. APP=<name> required; FORCE=1 rotates existing values."
    task sync_secrets: :environment do
      app = ENV["APP"].to_s.strip
      abort "Usage: bin/rails roe:fly:sync_secrets APP=<fly-app-name> [FORCE=1]" if app.empty?

      force  = ENV["FORCE"] == "1"
      result = FlySecretsSync.run(app: app, force: force, logger: Rails.logger)

      puts ""
      if result.set_keys.any?
        puts "#{force ? 'Rotated' : 'Staged'} #{result.set_keys.size} secret(s) on Fly app '#{app}':"
        result.set_keys.each { |k| puts "  ✓ #{k}" }
      end
      if result.skipped_keys.any?
        puts ""
        puts "Already set on Fly (skipped — pass FORCE=1 to rotate):"
        result.skipped_keys.each { |k| puts "  · #{k}" }
      end
      if result.set_keys.any?
        puts ""
        puts "Done. Secrets are STAGED — they take effect on the next `fly deploy`."
      end
    rescue => e
      abort e.message
    end
  end
end

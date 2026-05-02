# frozen_string_literal: true

# Pre-flight diagnostics for the Roe update system. Run this before
# triggering an actual update from admin to verify the environment is
# healthy and the bug-fix code paths are in place. Does NOT trigger an
# update or modify any state — read-only checks only.
#
# Usage: bin/rails update:preflight

namespace :update do
  desc "Pre-flight checks for the update system (read-only diagnostics)"
  task preflight: :environment do
    checker = UpdatePreflightChecker.new
    checker.run
    exit(checker.failures.any? ? 1 : 0)
  end
end

class UpdatePreflightChecker
  attr_reader :failures, :warnings

  def initialize
    @failures = []
    @warnings = []
    @section = nil
  end

  def run
    section "Environment"
    check_external_tool("git",     "git --version")
    check_external_tool("sqlite3", "sqlite3 --version")
    check_external_tool("rsync",   "rsync --version | head -1")

    section "Roe paths"
    check("ROE_ROOT resolves",            -> { Dir.exist?(RoeSitePaths::ROE_ROOT) },         RoeSitePaths::ROE_ROOT)
    check("SITE_PATH resolves",           -> { Dir.exist?(RoeSitePaths::SITE_PATH) },        RoeSitePaths::SITE_PATH)
    check("VERSION file at ROE_ROOT",     -> { File.exist?(version_path) },                  version_path)
    check_version_readable

    section "Staging directory"
    check("staging/ exists",              -> { Dir.exist?(staging_path) },                    staging_path)
    check("staging/ is empty (Bug 3)",    -> { Dir.exist?(staging_path) && Dir.empty?(staging_path) },
          "non-empty staging/ would block validate_prerequisites — clean it up before testing")

    section "Sourcehut connectivity"
    check_sourcehut_reachable
    check_update_check

    section "Database files"
    check_database_files

    section "SQLite backup smoke test"
    check_sqlite_backup_roundtrip

    section "Bug fixes present in source"
    check_source_contains("Bug 1 (SITE_PATH ENV override)",
      "current/config/application.rb",
      "ENV['ROE_SITE_PATH']")
    check_source_contains("Bug 2 (migrations from staging)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "staging_app = File.join(RoeSitePaths::ROE_ROOT, 'staging')")
    check_source_contains("Bug 3 (validate accepts empty staging)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "Dir.empty?(staging)")
    check_source_contains("Bug 4 (writes VERSION to root)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "write_root_version_file")
    check_source_contains("Bug 5 (restart skipped in dev)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "unless Rails.env.production?")
    check_source_contains("Bug 6 (SQLite .backup not cp)",
      "current/app/services/roe_updater/backup_manager.rb",
      ".backup")
    check_source_contains("Bug 7 (mock gated by ENV)",
      "current/app/services/roe_updater/version_checker.rb",
      "ROE_MOCK_UPDATE")
    check_source_contains("sync_root_files step",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "sync_root_files")

    section "Root file sync sources"
    RoeUpdater::UpdateOrchestrator::ROOT_SYNC_FILES.each do |fname|
      source = File.join(RoeSitePaths::ROE_ROOT, "current", fname)
      check("current/#{fname} exists (source for sync)", -> { File.exist?(source) }, source)
    end

    summary
  end

  private

  def section(label)
    puts ""
    puts "── #{label} #{'─' * (60 - label.length)}"
  end

  def check(label, predicate, detail = nil)
    ok = predicate.call
    if ok
      puts "  ✓ #{label}#{detail ? "  (#{detail})" : ""}"
    else
      puts "  ✗ #{label}#{detail ? "  → #{detail}" : ""}"
      @failures << label
    end
  rescue => e
    puts "  ✗ #{label}  → raised: #{e.class}: #{e.message}"
    @failures << label
  end

  def warn(label, detail = nil)
    puts "  ⚠ #{label}#{detail ? "  → #{detail}" : ""}"
    @warnings << label
  end

  def info(label, detail = nil)
    puts "  ⊘ #{label}#{detail ? "  (#{detail})" : ""}"
  end

  def check_external_tool(name, cmd)
    output = `#{cmd} 2>&1`.lines.first&.strip
    if $?.success?
      puts "  ✓ #{name}: #{output}"
    else
      puts "  ✗ #{name}: not found or failed (#{output})"
      @failures << "#{name} not available"
    end
  end

  def check_version_readable
    return unless File.exist?(version_path)
    config = YAML.load_file(version_path) || {}
    version = config["version"] || config[:version]
    if version
      puts "  ✓ Current version: #{version}"
    else
      puts "  ✗ VERSION file has no `version` key"
      @failures << "version key missing"
    end
  rescue => e
    puts "  ✗ VERSION file unreadable: #{e.message}"
    @failures << "version file unreadable"
  end

  def check_sourcehut_reachable
    if ENV["ROE_MOCK_UPDATE"].present?
      info("ROE_MOCK_UPDATE=#{ENV['ROE_MOCK_UPDATE']}", "skipping live Sourcehut check (mock active)")
      return
    end

    output = `git ls-remote --tags #{RoeUpdater::VersionChecker::GIT_REMOTE_URL} 2>&1`
    if $?.success?
      tag_count = output.lines.count
      puts "  ✓ git.sr.ht reachable: #{tag_count} tag refs found"
    else
      puts "  ✗ Cannot reach git.sr.ht for tag listing"
      puts "     #{output.lines.first&.strip}"
      @failures << "sourcehut unreachable"
    end
  end

  def check_update_check
    info = RoeUpdater::VersionChecker.check_for_updates
    if info.nil?
      warn("check_for_updates returned nil", "either no tags found, network failure, or repo private")
    else
      puts "  ✓ check_for_updates: current=#{info[:current_version]}, latest=#{info[:latest_version]}, available=#{info[:update_available]}"
    end
  end

  def check_database_files
    [
      ["development", "development.sqlite3"],
      ["production",  "production.sqlite3"]
    ].each do |env, fname|
      path = File.join(RoeSitePaths::SITE_DB_PATH, env, fname)
      if File.exist?(path)
        size_mb = (File.size(path) / 1024.0 / 1024.0).round(1)
        puts "  ✓ #{env} DB: #{path} (#{size_mb} MB)"
      else
        info("#{env} DB not present", path)
      end
    end
  end

  def check_sqlite_backup_roundtrip
    source = File.join(RoeSitePaths::SITE_DB_PATH, "development", "development.sqlite3")
    unless File.exist?(source)
      info("Skipped — no development DB to test against", source)
      return
    end

    Dir.mktmpdir("roe_preflight_") do |tmp|
      backup = File.join(tmp, "snapshot.sqlite3")

      # Test .backup
      out = `sqlite3 '#{source}' ".backup '#{backup}'" 2>&1`
      unless $?.success?
        puts "  ✗ sqlite3 .backup failed: #{out}"
        @failures << ".backup failed"
        return
      end
      puts "  ✓ .backup wrote snapshot (#{(File.size(backup) / 1024.0).round} KB)"

      # Test the snapshot is readable
      tables_out = `sqlite3 '#{backup}' ".tables" 2>&1`.strip
      unless $?.success? && tables_out.length > 0
        puts "  ✗ snapshot unreadable or empty"
        @failures << "snapshot unreadable"
        return
      end
      puts "  ✓ snapshot opens cleanly (#{tables_out.split.count} tables)"
    end
  end

  def check_source_contains(label, relative_path, needle)
    full = File.join(RoeSitePaths::ROE_ROOT, relative_path)
    if !File.exist?(full)
      puts "  ✗ #{label}  → #{relative_path} missing"
      @failures << label
    elsif File.read(full).include?(needle)
      puts "  ✓ #{label}"
    else
      puts "  ✗ #{label}  → expected `#{needle}` in #{relative_path}"
      @failures << label
    end
  end

  def summary
    puts ""
    puts "═" * 64
    if @failures.empty? && @warnings.empty?
      puts "✓ All preflight checks passed. Safe to run an update from admin."
    elsif @failures.empty?
      puts "✓ Preflight passed with #{@warnings.count} warning(s) — review above."
    else
      puts "✗ #{@failures.count} preflight failure(s):"
      @failures.each { |f| puts "    - #{f}" }
      puts ""
      puts "Fix the failures above before triggering a real update."
    end
    puts "═" * 64
  end

  def version_path
    @version_path ||= File.join(RoeSitePaths::ROE_ROOT, "VERSION")
  end

  def staging_path
    @staging_path ||= File.join(RoeSitePaths::ROE_ROOT, "staging")
  end
end

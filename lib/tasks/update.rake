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
    check_roe_paths

    section "Staging directory"
    check_staging

    section "Update mirrors"
    check_mirrors_reachable
    check_update_check

    section "Database files"
    check_database_files

    section "SQLite backup smoke test"
    check_sqlite_backup_roundtrip

    section "Bug fixes present in source"
    check_bug_fixes_present

    section "Root file sync sources"
    check_root_sync_sources

    summary
  end

  # The checks below need no network and change nothing, so the test suite
  # runs them too (test/tasks/update_preflight_test.rb) — a fix that moves
  # breaks a test instead of quietly turning the preflight red.

  def check_roe_paths
    check("ROE_ROOT resolves",            -> { Dir.exist?(RoeSitePaths::ROE_ROOT) },         RoeSitePaths::ROE_ROOT)
    check("SITE_PATH resolves",           -> { Dir.exist?(RoeSitePaths::SITE_PATH) },        RoeSitePaths::SITE_PATH)
    check("VERSION file at ROE_ROOT",     -> { File.exist?(version_path) },                  version_path)
    check_version_readable
  end

  # staging/ only exists while an update runs — Downloader creates it and a
  # finished or rolled-back update removes it. Absent is the normal state.
  # Only leftover content blocks an update (validate_prerequisites).
  def check_staging
    check("staging/ is absent or empty (Bug 3)",
          -> { !Dir.exist?(staging_path) || Dir.empty?(staging_path) },
          staging_path,
          on_fail: "#{staging_path} has leftover content, which blocks the next update — " \
                   "an update is running, or one crashed; clean it up before updating")
  end

  def check_bug_fixes_present
    check_source_contains("Bug 1 (SITE_PATH ENV override)",
      "current/config/application.rb",
      /ENV\[["']ROE_SITE_PATH["']\]/)
    check_source_contains("Bug 2 (migrations tested from staging)",
      "current/app/services/roe_updater/migration_tester.rb",
      /staging_app_path = File\.join\(RoeSitePaths::ROE_ROOT, ["']staging["']\)/)
    check_source_contains("Bug 3 (validate accepts empty staging)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "Dir.empty?(staging)")
    check("Bug 4 (writes VERSION to root)",
          -> { RoeUpdater::UpdateOrchestrator.respond_to?(:write_version_files, true) &&
               source("current/app/services/roe_updater/update_orchestrator.rb")
                 .match?(/File\.join\(RoeSitePaths::ROE_ROOT, ["']VERSION["']\)/) },
          on_fail: "expected write_version_files to write ROE_ROOT/VERSION")
    check_source_contains("Bug 5 (restart skipped in dev)",
      "current/app/services/roe_updater/update_orchestrator.rb",
      "unless Rails.env.production?")
    check_source_contains("Bug 6 (SQLite .backup not cp)",
      "current/app/services/roe_updater/backup_manager.rb",
      ".backup")
    check_source_contains("Bug 7 (mock gated by ENV)",
      "current/app/services/roe_updater/version_checker.rb",
      "ROE_MOCK_UPDATE")
    check("sync_root_files step",
          -> { RoeUpdater::UpdateOrchestrator::STEPS.any? { |s| s[:name] == "syncing_root_files" } },
          on_fail: "expected a syncing_root_files step in UpdateOrchestrator::STEPS")
  end

  def check_root_sync_sources
    RoeUpdater::UpdateOrchestrator::ROOT_SYNC_FILES.each do |fname|
      source = File.join(RoeSitePaths::ROE_ROOT, "current", fname)
      check("current/#{fname} exists (source for sync)", -> { File.exist?(source) }, source)
    end
  end

  private

  def section(label)
    puts ""
    puts "── #{label} #{'─' * (60 - label.length)}"
  end

  # detail is shown either way; on_fail replaces it when the check fails,
  # for a message that only makes sense as a problem.
  def check(label, predicate, detail = nil, on_fail: nil)
    ok = predicate.call
    if ok
      puts "  ✓ #{label}#{detail ? "  (#{detail})" : ""}"
    else
      shown = on_fail || detail
      puts "  ✗ #{label}#{shown ? "  → #{shown}" : ""}"
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
    config = SiteFile.read_yaml(version_path) || {}
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

  # Checks the same list the updater walks, in the same order — a preflight
  # that hardcoded one host reported it reachable while the updater looked
  # somewhere else entirely, which is a green light for the wrong thing.
  #
  # Passes if ANY mirror answers, because that's the condition the updater
  # needs. Which one answered is worth printing: falling through to the last
  # mirror works but means the ones before it are down.
  def check_mirrors_reachable
    if ENV["ROE_MOCK_UPDATE"].present?
      info("ROE_MOCK_UPDATE=#{ENV['ROE_MOCK_UPDATE']}", "skipping live mirror check (mock active)")
      return
    end

    RoeUpdater::Forge.mirrors.each do |git_url|
      output = `git ls-remote --tags #{git_url} 2>&1`
      if $?.success?
        puts "  ✓ #{git_url} reachable: #{output.lines.count} tag refs found"
        return
      end

      puts "  · #{git_url} didn't answer, trying the next mirror"
    end

    puts "  ✗ No mirror could list tags"
    @failures << "no update mirror reachable"
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
      [ "development", "development.sqlite3" ],
      [ "production",  "production.sqlite3" ]
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

  # needle is a String (exact text) or a Regexp (for code where quote style
  # or spacing may vary — an exact string went stale on a ' → " change).
  def check_source_contains(label, relative_path, needle)
    text = source(relative_path)
    if text.nil?
      puts "  ✗ #{label}  → #{relative_path} missing"
      @failures << label
    elsif needle.is_a?(Regexp) ? text.match?(needle) : text.include?(needle)
      puts "  ✓ #{label}"
    else
      puts "  ✗ #{label}  → expected `#{needle.is_a?(Regexp) ? needle.source : needle}` in #{relative_path}"
      @failures << label
    end
  end

  def source(relative_path)
    full = File.join(RoeSitePaths::ROE_ROOT, relative_path)
    File.exist?(full) ? File.read(full) : nil
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

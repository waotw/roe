# Maintainer-only release prep. Bumps the version stamp across every
# place Roe's source repo encodes it, in one shot, so a release tag
# never ships with internally inconsistent version data.
#
# Updates, in order:
#   1. /VERSION                       (root, what VersionChecker reads
#                                      on a running install)
#   2. current/VERSION                (mirrors root, gets copied to
#                                      root on install)
#   3. _versions.yml manifest         (one file under the bundled docs
#                                      folder; maps each doc's path to
#                                      the Roe version in which it was
#                                      last meaningfully changed —
#                                      replaces the per-doc roe_version
#                                      frontmatter we used to stamp,
#                                      which caused noise churn every
#                                      rsync round-trip)
#   4. app/themes/*.css               ("Bundled with: Roe v…" header
#                                      line — always re-stamped so
#                                      every release advertises being
#                                      bundled with the current Roe,
#                                      even when the theme's own
#                                      version didn't move)
#
# Re-runnable: same VERSION twice is a no-op except release_date
# advancing to today. Run from current/:
#
#   bin/rails release:bump VERSION=0.0.20
#
# Convention reminder: bare version in code/files, `v` prefix on
# tags. So `VERSION=0.0.20`, but `git tag v0.0.20`.

require "yaml"
require "date"
require "set"
require "shellwords"
require "pathname"

namespace :release do
  desc "Bump version across VERSION files, site_templates docs, and bundled theme headers. Set VERSION=x.y.z."
  task bump: :environment do
    version = ENV["VERSION"].to_s.strip
    abort "Usage: bin/rails release:bump VERSION=x.y.z" if version.empty?
    unless version.match?(/\A\d+\.\d+\.\d+\z/)
      abort "VERSION must look like x.y.z (no `v` prefix; that's for tags only)."
    end

    today = Date.today.iso8601
    root = RoeSitePaths::ROE_ROOT

    puts "Bumping Roe to #{version} (release_date: #{today})"
    puts ""

    touched = touched_paths_since_last_tag(root)

    bump_version_files(root, version, today)
    bump_docs_manifest(root, version, touched)
    bump_theme_headers(root, version, touched)

    puts ""
    puts "Done. Review with `git diff`, then:"
    puts "  git add -p"
    puts "  git commit -m 'Bump to #{version}'"
    puts "  git tag v#{version}"
    puts "  git push && git push --tags"
  end

  def bump_version_files(root, version, today)
    puts "VERSION files:"
    [
      File.join(root, "VERSION"),
      File.join(root, "current", "VERSION")
    ].each do |path|
      unless File.exist?(path)
        puts "  ! #{relative(path, root)} missing — skipped"
        next
      end

      config = YAML.safe_load_file(path) || {}
      config["version"] = version
      config["release_date"] = today
      File.write(path, config.to_yaml)
      puts "  ✓ #{relative(path, root)}"
    end
  end

  # Writes lib/site_templates/minimum/documentation/roe/_versions.yml
  # — a single flat mapping of each doc's path (relative to the docs
  # folder) to the Roe version in which the doc was last meaningfully
  # changed. Replaces the per-doc `roe_version:` frontmatter approach
  # (every rsync round-trip restamped every file's frontmatter,
  # producing a wall of meaningless diffs in git status).
  #
  # Update policy for each doc on disk:
  #   - in touched set (changed since last tag) → stamp at new version
  #   - new doc not yet in manifest → stamp at new version
  #   - otherwise → keep its existing version (last meaningful change)
  #
  # Manifest entries for files that no longer exist on disk are
  # pruned so the manifest stays in sync with reality.
  #
  # Ships with the docs (under lib/site_templates), gets installed to
  # /site/documentation/roe/_versions.yml on next install, and is
  # readable at runtime by the docs view to show "Updated in Roe X.Y.Z"
  # alongside each doc.
  def bump_docs_manifest(root, version, touched)
    docs_root = File.join(root, "current", "lib", "site_templates", "minimum", "documentation", "roe")

    unless Dir.exist?(docs_root)
      puts ""
      puts "Docs manifest: docs folder not found at #{relative(docs_root, root)} — skipped"
      return
    end

    manifest_path = File.join(docs_root, "_versions.yml")
    manifest = File.exist?(manifest_path) ? (YAML.safe_load_file(manifest_path) || {}) : {}

    files = Dir.glob(File.join(docs_root, "**", "*.md"))
    on_disk_keys = files.map { |path| manifest_key(path, docs_root) }.to_set

    added = updated = kept = removed = 0

    files.each do |path|
      key = manifest_key(path, docs_root)
      should_stamp = touched.include?(path) || !manifest.key?(key)

      if should_stamp
        if manifest.key?(key)
          if manifest[key] == version
            kept += 1
          else
            manifest[key] = version
            updated += 1
          end
        else
          manifest[key] = version
          added += 1
        end
      else
        kept += 1
      end
    end

    # Prune entries for docs that no longer exist on disk.
    manifest.keys.reject { |k| on_disk_keys.include?(k) }.each do |stale_key|
      manifest.delete(stale_key)
      removed += 1
    end

    # Sort alphabetically for stable, diff-friendly output across runs.
    File.write(manifest_path, manifest.sort.to_h.to_yaml)

    puts ""
    puts "Docs manifest (#{relative(manifest_path, root)}):"
    puts "  ✓ #{updated} stamped at #{version}" if updated > 0
    puts "  + #{added} added at #{version}"     if added > 0
    puts "  · #{kept} unchanged"                if kept > 0
    puts "  − #{removed} pruned (no longer on disk)" if removed > 0
  end

  # Path inside the docs folder, used as the manifest key. Preserves
  # subdirectories so docs under tutorials/ etc. don't collide with
  # top-level docs of the same basename.
  def manifest_key(path, docs_root)
    Pathname.new(path).relative_path_from(Pathname.new(docs_root)).to_s
  end

  def bump_theme_headers(root, version, touched)
    pattern = File.join(root, "current", "app", "themes", "*.css")
    files = Dir.glob(pattern)
    changed = 0
    no_line = 0
    untouched = 0

    files.each do |path|
      # Same smart-bump principle: "Bundled with:" becomes a
      # freshness marker — the Roe version in which this theme was
      # last touched.
      unless touched.include?(path)
        untouched += 1
        next
      end

      content = File.read(path)

      # Replace `Bundled with: Roe vX.Y.Z` preserving the leading
      # whitespace + comment indentation that's standard in theme
      # headers. Case-insensitive on "Roe" defensively.
      new_content = content.sub(/^(\s*Bundled with:\s*Roe\s+v)[\d.]+/i) do
        "#{Regexp.last_match(1)}#{version}"
      end

      if new_content == content
        no_line += 1
      else
        File.write(path, new_content)
        changed += 1
        puts "  ✓ themes/#{File.basename(path)}"
      end
    end

    puts ""
    puts "Themes:"
    puts "  ✓ #{changed} stamped at #{version}" if changed > 0
    puts "  · #{untouched} unchanged since last tag" if untouched > 0
    puts "  · #{no_line} touched but no `Bundled with:` line (skipped)" if no_line > 0
  end

  # Returns the set of absolute paths under current/ that have been
  # touched (committed OR uncommitted) since the most recent git tag.
  # Used by the smart-bump logic so a release only stamps the new Roe
  # version onto files that actually moved.
  #
  # If there's no prior tag (e.g. the very first release on this
  # repo), every candidate file is considered touched so the first
  # bump stamps everything as a baseline.
  def touched_paths_since_last_tag(root)
    current = File.join(root, "current")
    last_tag = `cd #{current.shellescape} && git describe --tags --abbrev=0 2>/dev/null`.strip

    if last_tag.empty?
      puts "No prior git tag found — first release, stamping all candidate files."
      candidates = Dir.glob([
        File.join(current, "lib", "site_templates", "**", "*.md"),
        File.join(current, "app", "themes", "*.css")
      ])
      return candidates.to_set
    end

    relative_paths = Dir.chdir(current) do
      # Files added / modified / renamed in commits between the last
      # tag and HEAD.
      committed = `git diff --name-only #{last_tag.shellescape}..HEAD --diff-filter=AMR -- lib/site_templates app/themes 2>/dev/null`.split("\n")

      # Files with uncommitted modifications in the working tree.
      modified = `git diff --name-only -- lib/site_templates app/themes 2>/dev/null`.split("\n")

      # Files that exist on disk but aren't tracked yet (new docs/
      # themes the dev hasn't `git add`ed).
      untracked = `git ls-files --others --exclude-standard -- lib/site_templates app/themes 2>/dev/null`.split("\n")

      (committed + modified + untracked).map(&:strip).reject(&:empty?).uniq
    end

    relative_paths.map { |p| File.join(current, p) }.to_set
  end

  def relative(path, root)
    path.sub(root + "/", "")
  end
end

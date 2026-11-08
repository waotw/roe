# Release-time check for bin/sync-from-site: a doc in site/ that is an exact
# copy of an OLDER committed version of Roe's copy.
#
# The docs step mirrors site/documentation/roe/ over Roe's copy, so whatever
# site/ holds gets committed. Twice in 2026 site/ held old versions — a Site
# Sync pull brought back the live site's stale copies — and the sync quietly
# committed months-old docs over newer rewrites. Nobody writes a doc that
# matches an earlier commit byte for byte; something put it back. So such a
# file is held back and named, with the command that shows what it would undo.
#
# Read-only: git and file reads, no writes.
require "open3"

class DocsRevertCheck
  Finding = Struct.new(:rel, :commit, :date, keyword_init: true)

  # site_dir: site/documentation/roe. app_rel: the matching path inside the
  # repo (lib/site_templates/minimum/documentation/roe). repo: current/.
  def initialize(site_dir:, app_rel:, repo:)
    # Absolute, because git runs with -C: a relative file path would be
    # looked up inside the repo, found missing, and silently pass.
    @site_dir = File.expand_path(site_dir.to_s)
    @app_rel  = app_rel.to_s
    @repo     = File.expand_path(repo.to_s)
  end

  # Every site/ doc that differs from Roe's committed copy but matches an
  # earlier commit of it. rel is relative to site_dir.
  def findings
    Dir.glob(File.join(@site_dir, "**", "*")).sort.filter_map do |path|
      next unless File.file?(path)

      rel = path.delete_prefix("#{@site_dir}/")
      check(rel, path)
    end
  end

  private

  def check(rel, path)
    repo_path = File.join(@app_rel, rel)
    head = git("rev-parse", "HEAD:#{repo_path}")
    return nil unless head # new in site/, nothing to go back to

    mine = git("hash-object", path)
    return nil if mine.nil? || mine == head

    # When each version of the file first appeared, oldest first. Going
    # backwards means site/ holds text that first appeared BEFORE Roe's
    # current text. The reverse — site/ newer than Roe's — is ordinary
    # forward work, and also how restoring lost text looks: Roe's copy then
    # holds the old text, and the restored file a version that came after it.
    first_seen = {}
    git("log", "--reverse", "--format=%H %ad", "--date=short", "HEAD", "--", repo_path).to_s.each_line do |line|
      sha, date = line.split
      blob = git("rev-parse", "#{sha}:#{repo_path}")
      first_seen[blob] ||= { index: first_seen.size, sha: sha, date: date } if blob
    end

    mine_seen = first_seen[mine]
    head_seen = first_seen[head]
    return nil unless mine_seen && head_seen && mine_seen[:index] < head_seen[:index]

    Finding.new(rel: rel, commit: mine_seen[:sha][0, 7], date: mine_seen[:date])
  end

  def git(*args)
    out, status = Open3.capture2("git", "-C", @repo, *args, err: File::NULL)
    status.success? ? out.strip : nil
  end
end

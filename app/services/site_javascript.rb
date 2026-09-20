# Site-facing vanilla JS (search.js, gallery.js, checkout.js, footnotes.js).
#
# The shipped source is app/site_js/. On first boot each file is copied
# into site/javascript/ — once, if missing — and from then on the site
# owns it. Roe never rewrites, moves or renames anything in site/javascript/
# on boot: site/ travels between installs by Site Sync, and a change made
# by new code lands on a live site still running the old code
# (conventions.md, rule 8).
#
# Updates reach a site the same way theme updates do. Each shipped file
# carries a header with its version and a fingerprint of its body;
# ShippedFileInspector compares the site's copy to the shipped one, and the
# Updates page offers the newer version — in one click when the copy is
# untouched, with a diff and a download of the site's copy when it has been
# edited. Nothing changes until someone chooses.
#
# Resolution is site copy first, shipped source second, for the dynamic
# controller and the static generator alike.
module SiteJavascript
  module_function

  def source_dir
    Rails.root.join("app", "site_js").to_s
  end

  def site_dir
    File.join(RoeSitePaths::SITE_PATH, "javascript")
  end

  # Names of the files Roe ships.
  def shipped_names
    Dir.glob(File.join(source_dir, "*.js")).map { |f| File.basename(f) }.sort
  end

  # Absolute path for a filename — the site copy if present, else the
  # shipped source. Basename-only, so a request can't escape the directory.
  def path(filename)
    name = File.basename(filename.to_s)
    site = File.join(site_dir, name)
    File.exist?(site) ? site : File.join(source_dir, name)
  end

  def exist?(filename)
    File.exist?(path(filename))
  end

  # Copy any shipped JS not already in site/javascript so the site carries
  # its own copies. Never touches a file already there.
  def seed!
    undo_roe_subfolder!
    FileUtils.mkdir_p(site_dir)
    Dir.glob(File.join(source_dir, "*.js")).each do |src|
      dest = File.join(site_dir, File.basename(src))
      FileUtils.cp(src, dest) unless File.exist?(dest)
    end
  rescue => e
    Rails.logger.warn "[SiteJavascript] seed skipped: #{e.class} #{e.message}"
  end

  # One update report per shipped file, for the Updates page.
  def reports
    shipped_names.map do |name|
      [ name, ShippedFileInspector.report(
        bundled_path:   File.join(source_dir, name),
        installed_path: File.join(site_dir, name)
      ) ]
    end.to_h
  end

  # Replace the site's copy with the shipped one. The single write path for
  # an update, and it only ever runs because someone clicked.
  def update!(filename)
    name = File.basename(filename.to_s)
    src  = File.join(source_dir, name)
    raise ArgumentError, "Roe doesn't ship #{name}" unless File.exist?(src)

    FileUtils.mkdir_p(site_dir)
    FileUtils.cp(src, File.join(site_dir, name))
  end

  # ── nightly.4 undo ─────────────────────────────────────────────────────
  #
  # One nightly moved these files into site/javascript/roe/ and renamed the
  # originals with a date suffix. That broke the rule above and a live
  # site with it. This puts things back on the first boot that finds the
  # layout, and only then: remove roe/ (Roe made it, Roe removes it) and
  # restore each renamed file when nothing sits where it came from. Sites
  # that never ran that nightly have no roe/ folder and nothing happens.
  RETIRED_SUFFIX = ".2026-09-19".freeze

  def undo_roe_subfolder!
    roe_dir = File.join(site_dir, "roe")
    return unless File.directory?(roe_dir)

    shipped_names.each do |name|
      original = File.join(site_dir, name)
      retired  = "#{original}#{RETIRED_SUFFIX}"
      next unless File.file?(retired)

      if File.exist?(original)
        Rails.logger.info "[SiteJavascript] #{name} already present; leaving #{File.basename(retired)} for you to delete"
      else
        FileUtils.mv(retired, original)
        Rails.logger.info "[SiteJavascript] restored #{name} from #{File.basename(retired)}"
      end
    end

    FileUtils.rm_rf(roe_dir)
    Rails.logger.info "[SiteJavascript] removed site/javascript/roe/ — updates now go through Admin → Updates"
  end
end

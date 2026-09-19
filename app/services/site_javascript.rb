# Site-facing vanilla JS (search.js, gallery.js, checkout.js, footnotes.js).
#
# The shipped source is app/site_js/. On boot it's written into
# site/javascript/roe/ — Roe's folder, rewritten every boot, so a fix that
# ships with an update reaches every site the moment it starts. The same
# split as documentation/roe/: the roe/ subfolder is Roe's, everything
# beside it is the site's.
#
# To customise a file, copy it up one level: site/javascript/search.js wins
# over site/javascript/roe/search.js, and Roe never touches it. Resolution
# is site → roe → shipped source, for the dynamic controller and the static
# generator alike, so an override wins in either mode.
module SiteJavascript
  module_function

  def source_dir
    Rails.root.join("app", "site_js").to_s
  end

  def site_dir
    File.join(RoeSitePaths::SITE_PATH, "javascript")
  end

  # Roe's own copies, refreshed on every boot.
  def roe_dir
    File.join(site_dir, "roe")
  end

  # Names of the files Roe ships — the set that roe/ owns.
  def shipped_names
    Dir.glob(File.join(source_dir, "*.js")).map { |f| File.basename(f) }
  end

  # Absolute path for a filename: the site's override if present, else Roe's
  # copy in roe/, else the shipped source. Basename-only, so a request can't
  # escape the directory.
  def path(filename)
    name = File.basename(filename.to_s)
    [ File.join(site_dir, name), File.join(roe_dir, name), File.join(source_dir, name) ]
      .find { |p| File.exist?(p) } || File.join(source_dir, name)
  end

  def exist?(filename)
    File.exist?(path(filename))
  end

  # True when the site has its own copy shadowing Roe's.
  def overridden?(filename)
    File.exist?(File.join(site_dir, File.basename(filename.to_s)))
  end

  # Write Roe's copies into site/javascript/roe/, overwriting whatever is
  # there — that folder is Roe's. Never touches files beside it.
  #
  # Also the one-time move for sites from before roe/ existed: the seeder
  # used to put these same files directly in site/javascript/, where they
  # now read as overrides and would pin the site to the old code forever.
  # An untouched seed is renamed out of the way rather than deleted, so a
  # copy someone did edit is still there to put back. Only Roe's own
  # filenames are considered, and only on the boot that creates roe/ —
  # after that a Roe filename in site/javascript/ is an override and stays.
  def seed!
    # Only before roe/ exists — that's the one boot where a Roe filename in
    # site/javascript/ is the old seed rather than a deliberate override.
    retire_pre_roe_copies! unless File.directory?(roe_dir)

    FileUtils.mkdir_p(roe_dir)
    Dir.glob(File.join(source_dir, "*.js")).each do |src|
      dest = File.join(roe_dir, File.basename(src))
      FileUtils.cp(src, dest) unless File.exist?(dest) && FileUtils.identical?(src, dest)
    end
  rescue => e
    Rails.logger.warn "[SiteJavascript] seed skipped: #{e.class} #{e.message}"
  end

  RETIRED_SUFFIX_DATE = "2026-09-19".freeze

  def retire_pre_roe_copies!
    shipped_names.each do |name|
      old = File.join(site_dir, name)
      next unless File.file?(old)

      retired = "#{old}.#{RETIRED_SUFFIX_DATE}"
      retired = "#{old}.#{RETIRED_SUFFIX_DATE}.#{Time.now.to_i}" if File.exist?(retired)
      FileUtils.mv(old, retired)
      Rails.logger.info "[SiteJavascript] moved #{name} aside as #{File.basename(retired)} — Roe's copy now lives in javascript/roe/; copy it back up to override"
    end
  end
end

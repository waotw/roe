# Site-facing vanilla JS (search.js, gallery.js, checkout.js). The shipped
# source is app/site_js/; on boot it's seeded into site/javascript/ so the site
# is self-contained. Resolution prefers the site copy, falling back to the
# shipped source — the dynamic controller and the static generator both use
# this, so a per-site override wins in either mode.
module SiteJavascript
  module_function

  def source_dir
    Rails.root.join("app", "site_js").to_s
  end

  def site_dir
    File.join(RoeSitePaths::SITE_PATH, "javascript")
  end

  # Absolute path for a filename — the site copy if present, else the shipped
  # source. Basename-only, so a request can't escape the directory.
  def path(filename)
    name = File.basename(filename.to_s)
    site = File.join(site_dir, name)
    File.exist?(site) ? site : File.join(source_dir, name)
  end

  def exist?(filename)
    name = File.basename(filename.to_s)
    File.exist?(File.join(site_dir, name)) || File.exist?(File.join(source_dir, name))
  end

  # Copy any shipped JS not already in site/javascript so the site carries its
  # own copies. Never clobbers a file already there (a per-site override stays).
  def seed!
    FileUtils.mkdir_p(site_dir)
    Dir.glob(File.join(source_dir, "*.js")).each do |src|
      dest = File.join(site_dir, File.basename(src))
      FileUtils.cp(src, dest) unless File.exist?(dest)
    end
  rescue => e
    Rails.logger.warn "[SiteJavascript] seed skipped: #{e.class} #{e.message}"
  end
end

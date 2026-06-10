class PageGenerator
  PAGES_PATH = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "pages"))

  # The default pages (currently just home.md) now ship as files under
  # lib/site_templates/minimum/pages/ and are installed by
  # ConfigGenerator.generate_all → SiteTemplates::Loader. This method
  # remains as the initializer's call site for any page-level setup
  # that isn't a static template — today that's the theme compat shim.
  def self.generate_defaults
    activate_default_theme
  end

  # Backward-compatibility safety net for sites whose existing site.yml
  # is missing the theme key entirely (pre-template-kit installs).
  # Fresh installs get `theme: { active: "default" }` from the template,
  # so this method returns immediately. Kept so an old site.yml never
  # boots without a theme set.
  def self.activate_default_theme
    site_yml_path = File.join(RoeSitePaths::SITE_PATH, "system", "global", "site.yml")
    return unless File.exist?(site_yml_path)

    config = YAML.load_file(site_yml_path) || {}
    return if config["theme"].present?

    config["theme"] = "default"
    File.write(site_yml_path, config.to_yaml.sub(/\A---\n/, ""))
    Rails.logger.info "Set default theme in site.yml"
  end

  private

  def self.generate_archive_page
    content = <<~MARKDOWN
      ---
      title: Archive
      url_name: archive
      status: published
      ---

      # Archive

      All posts, newest first.

      ```collection
      source: posts
      order: date
      limit: all
      ```
    MARKDOWN

    File.write(PAGES_PATH.join("archive.md"), content)
    Rails.logger.info "Created default archive.md"
  end
end

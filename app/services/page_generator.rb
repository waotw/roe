class PageGenerator
  PAGES_PATH = Pathname.new(File.join(RoeSitePaths::SITE_PATH, 'pages'))

  def self.generate_defaults
    FileUtils.mkdir_p(PAGES_PATH)

    generate_home_page unless File.exist?(PAGES_PATH.join('home.md'))
    activate_default_theme
  end

  def self.activate_default_theme
    site_yml_path = File.join(RoeSitePaths::SITE_PATH, 'system', 'global', 'site.yml')
    return unless File.exist?(site_yml_path)

    config = YAML.load_file(site_yml_path) || {}
    return if config['theme'].present?

    config['theme'] = 'default'
    File.write(site_yml_path, config.to_yaml.sub(/\A---\n/, ''))
    Rails.logger.info "Set default theme in site.yml"
  end

  private

  def self.generate_home_page
    content = <<~MARKDOWN
      ---
      title: Home
      url_name: home
      status: published
      ---

      # Welcome

      ```collection
      heading: Latest Posts
      source: posts
      limit: 10
      show_more: true
      ```
    MARKDOWN

    File.write(PAGES_PATH.join('home.md'), content)
    Rails.logger.info "Created default home.md"
  end

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

    File.write(PAGES_PATH.join('archive.md'), content)
    Rails.logger.info "Created default archive.md"
  end
end

class PageGenerator
  PAGES_PATH = Rails.root.join('site/pages')

  def self.generate_defaults
    FileUtils.mkdir_p(PAGES_PATH)

    generate_home_page unless File.exist?(PAGES_PATH.join('home.md'))
    generate_archive_page unless File.exist?(PAGES_PATH.join('archive.md'))
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

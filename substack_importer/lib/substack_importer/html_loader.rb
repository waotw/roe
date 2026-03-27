# frozen_string_literal: true

module SubstackImporter
  class HtmlLoader
    attr_reader :posts_dir, :unmatched_files

    def initialize(posts_dir)
      @posts_dir = posts_dir
      @html_files = {}
      @unmatched_files = []
    end

    def load
      return unless Dir.exist?(@posts_dir)

      Dir.glob(File.join(@posts_dir, "**", "*.html")).each do |path|
        basename = File.basename(path, ".html")
        @html_files[basename] = path
      end

      @html_files
    end

    def match_to_posts(posts)
      unmatched_posts = []

      posts.each do |post|
        matched = find_html_for_post(post)

        if matched
          post.html_path = matched
          post.html_content = File.read(matched)
          @html_files.delete(File.basename(matched, ".html"))
        else
          unmatched_posts << post
        end
      end

      @unmatched_files = @html_files.values

      {
        matched: posts.count(&:html_path),
        unmatched_posts: unmatched_posts,
        unmatched_files: @unmatched_files
      }
    end

    private

    def find_html_for_post(post)
      # Try exact slug match first
      if @html_files.key?(post.slug)
        return @html_files[post.slug]
      end

      # Try matching by post_id prefix in filename
      @html_files.each do |basename, path|
        return path if basename.start_with?(post.id)
      end

      nil
    end
  end
end

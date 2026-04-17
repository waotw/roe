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
          html_content = File.read(matched)
          post.html_content = html_content

          # Extract cover image from HTML meta tags if not already set
          post.cover_image = extract_cover_image(html_content) if post.cover_image.nil? || post.cover_image.empty?

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

    def extract_cover_image(html)
      return nil if html.nil? || html.empty?

      doc = Nokogiri::HTML(html)

      # Try various meta tags that might contain the cover image
      # Order matters - try the most specific ones first
      selectors = [
        'meta[property="og:image"]',
        'meta[name="twitter:image"]',
        'meta[property="twitter:image"]',
        'meta[name="image"]',
        'meta[itemprop="image"]'
      ]

      selectors.each do |selector|
        tag = doc.at_css(selector)
        if tag
          image_url = tag["content"].to_s
          return image_url if image_url.present? && image_url.start_with?("http")
        end
      end

      # Try to find first image in the content as fallback
      first_img = doc.at_css("img[data-attrs]")
      if first_img
        data_attrs = first_img["data-attrs"]
        if data_attrs
          begin
            parsed = JSON.parse(data_attrs)
            image_url = parsed["src"].to_s
            return image_url if image_url.present? && image_url.start_with?("http")
          rescue JSON::ParserError
            # Ignore parsing errors
          end
        end
      end

      nil
    rescue => e
      Rails.logger.debug "[SubstackImporter] Error extracting cover image: #{e.message}"
      nil
    end
  end
end

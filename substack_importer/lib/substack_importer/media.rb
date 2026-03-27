# frozen_string_literal: true

module SubstackImporter
  class Media
    attr_reader :output_root, :downloaded, :url_mappings

    def initialize(output_root:, replace_media: false, verbose: false)
      @output_root = output_root
      @replace_media = replace_media
      @verbose = verbose
      @downloaded = []
      @url_mappings = {} # remote_url => local_path
    end

    def download_all(posts)
      posts.each { |post| download_post_media(post) }
      @downloaded
    end

    def download_post_media(post)
      download_post_images(post)
      download_cover_image(post)
      download_podcast_artwork(post)
      download_audio(post)
      download_captions(post)
    end

    def replace_urls(markdown)
      result = markdown.dup
      root = File.expand_path(@output_root)

      @url_mappings.each do |remote, local|
        next if local.nil?

        relative = File.expand_path(local).sub(root + "/", "")
        local_path = "/#{relative}"

        # Try exact match first
        if result.include?(remote)
          result = result.gsub(remote, local_path)
          puts "  Replaced URL: #{remote[0..60]}... -> #{local_path}" if @verbose
        else
          # Try without HTML entities
          decoded = remote.gsub("&amp;", "&")
          if result.include?(decoded)
            result = result.gsub(decoded, local_path)
            puts "  Replaced decoded URL: #{decoded[0..60]}... -> #{local_path}" if @verbose
          else
            puts "  URL not found in markdown: #{remote[0..60]}..." if @verbose
          end
        end
      end
      result
    end

    def download_image(url, filename)
      dest = File.join(@output_root, "media", "images", filename)
      result = download_file(url, dest)
      @url_mappings[url] = result if result
      result
    end

    def download_audio_file(url, filename)
      dest = File.join(@output_root, "media", "audio", filename)
      download_file(url, dest)
    end

    def download_captions_file(url, filename)
      dest = File.join(@output_root, "media", "captions", filename)
      download_file(url, dest)
    end

    private

    def download_post_images(post)
      converter = Converter.new
      return unless post.html_content

      converter.convert(post.html_content)
      images = converter.collected_images

      images.each_with_index do |img, i|
        src = img[:src]
        next if src.nil? || src.empty? || src.start_with?("/")

        ext = File.extname(URI.parse(src).path).split("?").first
        ext = ".jpg" if ext.nil? || ext.empty?
        filename = "#{post.slug}-#{i + 1}#{ext}"

        download_image(src, filename)
      end
    rescue URI::InvalidURIError => e
      puts "  Invalid image URL: #{e.message}" if @verbose
    end

    def download_cover_image(post)
      return if post.cover_image.nil? || post.cover_image.empty?

      src = post.cover_image
      return if src.start_with?("/")

      ext = File.extname(URI.parse(src).path).split("?").first
      ext = ".jpg" if ext.nil? || ext.empty?
      filename = "#{post.slug}-cover#{ext}"

      download_image(src, filename)
    rescue URI::InvalidURIError => e
      puts "  Invalid cover image URL: #{e.message}" if @verbose
    end

    def download_podcast_artwork(post)
      return if post.podcast_episode_image_url.nil? || post.podcast_episode_image_url.empty?

      src = post.podcast_episode_image_url
      return if src.start_with?("/")

      ext = File.extname(URI.parse(src).path).split("?").first
      ext = ".jpg" if ext.nil? || ext.empty?
      filename = "#{post.slug}-artwork#{ext}"

      download_image(src, filename)
    rescue URI::InvalidURIError => e
      puts "  Invalid artwork URL: #{e.message}" if @verbose
    end

    def download_audio(post)
      url = post.podcast_url
      return if url.nil? || url.empty?

      filename = "#{post.slug}.mp3"
      download_audio_file(url, filename)
    end

    def download_captions(post)
      urls = post.caption_urls || []
      urls.each_with_index do |url, i|
        lang = "en"
        filename = "#{post.slug}.#{lang}.vtt"
        download_captions_file(url, filename)
      end
    end

    def download_file(url, dest, redirect_limit: 5)
      return dest if File.exist?(dest) && !@replace_media
      return nil if redirect_limit <= 0

      FileUtils.mkdir_p(File.dirname(dest))

      puts "  Downloading: #{url} -> #{dest}" if @verbose

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 120

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; SubstackImporter/#{VERSION})"

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        File.binwrite(dest, response.body)
        @downloaded << dest
        dest
      when Net::HTTPRedirection
        # Follow redirect
        new_url = response["location"]
        if new_url
          # Handle relative redirects
          new_url = URI.join(url, new_url).to_s unless new_url.start_with?("http")
          download_file(new_url, dest, redirect_limit: redirect_limit - 1)
        else
          puts "  Redirect without location: #{url}" if @verbose
          nil
        end
      else
        puts "  Download failed (#{response.code}): #{url}" if @verbose
        nil
      end
    rescue => e
      puts "  Download error: #{e.message}" if @verbose
      nil
    end
  end
end

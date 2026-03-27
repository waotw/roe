# frozen_string_literal: true

module SubstackImporter
  class Importer
    def initialize(options)
      @options = options
      @extractor = nil
      @csv_parser = nil
      @html_loader = nil
      @converter = nil
      @live_fetcher = nil
      @media = nil
      @frontmatter = nil
      @writer = nil
    end

    def run
      puts "Substack Importer v#{VERSION}"
      puts "=" * 40

      setup_components
      posts = extract_and_parse
      match_html(posts)
      fetch_live_data(posts) unless @options.no_fetch
      download_media(posts)
      write_output(posts)

      puts "\nDone!"
    rescue => e
      puts "\nError: #{e.message}"
      puts e.backtrace.first(5).join("\n") if @options.verbose
      exit 1
    ensure
      @extractor&.cleanup
    end

    private

    def setup_components
      @extractor = Extractor.new(@options.input)
      @converter = Converter.new(verbose: @options.verbose)
      @frontmatter = Frontmatter.new(output_root: @options.output)
      @writer = Writer.new(
        output_root: @options.output,
        dry_run: @options.dry_run,
        verbose: @options.verbose
      )
    end

    def extract_and_parse
      source_dir = @extractor.extract
      csv_path = @extractor.csv_path

      unless File.exist?(csv_path)
        raise ArgumentError, "posts.csv not found in input: #{source_dir}"
      end

      @csv_parser = CsvParser.new(csv_path)
      posts = @csv_parser.parse

      puts @csv_parser.summary

      # Apply filters
      posts = @csv_parser.filter(
        drafts: @options.drafts,
        type: @options.type,
        before: @options.before,
        after: @options.after
      )

      puts "\nAfter filtering: #{posts.count} posts to process"

      posts
    end

    def match_html(posts)
      posts_dir = @extractor.posts_dir

      unless Dir.exist?(posts_dir)
        puts "Warning: No posts/ directory found in input"
        return
      end

      @html_loader = HtmlLoader.new(posts_dir)
      @html_loader.load

      result = @html_loader.match_to_posts(posts)

      puts "\nHTML Matching:"
      puts "  Matched: #{result[:matched]}"
      puts "  Unmatched posts: #{result[:unmatched_posts].count}"
      puts "  Unmatched files: #{result[:unmatched_files].count}"

      if result[:unmatched_posts].any? && @options.verbose
        puts "\n  Posts without HTML:"
        result[:unmatched_posts].each { |p| puts "    - #{p.slug}" }
      end

      if result[:unmatched_files].any? && @options.verbose
        puts "\n  Files without posts:"
        result[:unmatched_files].each { |f| puts "    - #{File.basename(f)}" }
      end
    end

    def fetch_live_data(posts)
      @live_fetcher = LiveFetcher.new(
        base_url: @options.base_url,
        verbose: @options.verbose
      )

      @live_fetcher.fetch_posts(posts)
    end

    def download_media(posts)
      @media = Media.new(
        output_root: @options.output,
        replace_media: @options.replace_media,
        verbose: @options.verbose
      )

      puts "\nDownloading media..." if @options.verbose
      @media.download_all(posts)
    end

    def write_output(posts)
      manifest_entries = @live_fetcher&.manifest_entries || []

      posts.each do |post|
        next unless post.is_published || @options.drafts

        fm_yaml = @frontmatter.to_yaml(post)

        markdown = if post.html_content
          raw = @converter.convert(post.html_content)
          @media.replace_urls(raw)
        else
          ""
        end

        @writer.write_post(post, fm_yaml, markdown)
      end

      # Write manifest if there are missing media entries
      if manifest_entries.any?
        @writer.write_manifest(manifest_entries)
        puts "\n#{manifest_entries.count} posts have missing media — see #{@options.output}/missing_media.yml"
      end

      puts @writer.summary(posts, media_count: @media.downloaded.count, manifest_count: manifest_entries.count)
    end
  end
end

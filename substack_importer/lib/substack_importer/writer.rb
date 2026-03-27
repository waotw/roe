# frozen_string_literal: true

module SubstackImporter
  class Writer
    attr_reader :output_root, :written_files, :duplicates

    def initialize(output_root:, dry_run: false, verbose: false)
      @output_root = output_root
      @dry_run = dry_run
      @verbose = verbose
      @written_files = []
      @duplicates = 0
    end

    def write_post(post, frontmatter_yaml, markdown_body)
      if post.type == "page"
        dir = File.join(@output_root, "pages")
      else
        dir = File.join(@output_root, "posts")
      end

      FileUtils.mkdir_p(dir) unless @dry_run

      filename = "#{post.slug}.md"
      filepath = File.join(dir, filename)

      # Handle duplicates
      if File.exist?(filepath)
        existing = File.read(filepath)
        new_content = "#{frontmatter_yaml}\n#{markdown_body}\n"

        if existing != new_content
          @duplicates += 1
          filename = "#{post.slug}-duplicate-#{@duplicates}.md"
          filepath = File.join(dir, filename)
          puts "  ⚠ Duplicate: #{post.slug} -> #{filename}" if @verbose
        else
          puts "  Skipping (identical): #{filename}" if @verbose
          return filepath
        end
      end

      content = "#{frontmatter_yaml}\n#{markdown_body}\n"

      if @dry_run
        puts "  [DRY RUN] Would write: #{filepath}" if @verbose
        puts "  Content preview (first 100 chars): #{content[0..100]}..." if @verbose
      else
        File.write(filepath, content)
        @written_files << filepath
        puts "  ✓ Written: #{filepath}" if @verbose
      end

      filepath
    end

    def write_manifest(entries, filename = "missing_media.yml")
      return if entries.empty?

      filepath = File.join(@output_root, filename)

      manifest = {
        "missing_media" => entries.map do |entry|
          {
            "slug" => entry[:slug].to_s,
            "post_type" => entry[:post_type].to_s,
            "post_url" => entry[:post_url].to_s,
            "audience" => entry[:audience].to_s,
            "podcast_url" => entry[:podcast_url].to_s,
            "video_url" => entry[:video_url].to_s,
            "captions_url" => entry[:captions_url].to_s
          }
        end
      }

      yaml_content = <<~YAML
        # Missing media — fill in URLs manually, then re-run with:
        #   bin/import --manifest #{filename} --output #{@output_root}/
        #{manifest.to_yaml.sub(/^---\n/, "")}
      YAML

      if @dry_run
        puts "  [DRY RUN] Would write manifest: #{filepath}"
      else
        FileUtils.mkdir_p(@output_root)
        File.write(filepath, yaml_content)
        puts "  ✓ Manifest written: #{filepath}"
      end

      filepath
    end

    def summary(posts, media_count: 0, manifest_count: 0)
      published = posts.select(&:is_published)
      drafts = posts.reject(&:is_published)

      by_type = published.group_by(&:type)

      lines = ["\n#{"=" * 40}", "Import Summary", "=" * 40]
      lines << "Posts: #{by_type["newsletter"].to_a.count}"
      lines << "Podcasts: #{by_type["podcast"].to_a.count}"
      lines << "Pages: #{by_type["page"].to_a.count}"
      lines << "Drafts: #{drafts.count} (skipped unless --drafts)"
      lines << "Media: #{media_count} files downloaded"
      lines << "Missing Media: #{manifest_count}" if manifest_count > 0
      lines << "Duplicates: #{@duplicates}" if @duplicates > 0
      lines << "=" * 40

      lines.join("\n")
    end
  end
end

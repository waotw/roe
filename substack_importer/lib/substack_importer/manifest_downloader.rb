# frozen_string_literal: true

module SubstackImporter
  class ManifestDownloader
    def initialize(options)
      @manifest_path = options.manifest
      @output_root = options.output
      @replace_media = options.replace_media
      @verbose = options.verbose
    end

    def run
      puts "Substack Importer — Manifest Download Mode"
      puts "=" * 40

      manifest = load_manifest
      entries = manifest["missing_media"] || []

      puts "Found #{entries.count} entries in manifest"

      media = Media.new(
        output_root: @output_root,
        replace_media: @replace_media,
        verbose: @verbose
      )

      updated_count = 0
      skipped_count = 0
      error_count = 0

      entries.each do |entry|
        slug = entry["slug"]
        md_path = File.join(@output_root, "posts", "#{slug}.md")

        unless File.exist?(md_path)
          puts "  Warning: #{md_path} not found, skipping" if @verbose
          skipped_count += 1
          next
        end

        downloaded = download_entry_media(entry, media)

        if downloaded.any?
          patch_frontmatter(md_path, downloaded)
          updated_count += 1
        else
          skipped_count += 1
        end
      rescue => e
        puts "  Error processing #{slug}: #{e.message}"
        error_count += 1
      end

      puts "\n#{"=" * 40}"
      puts "Files updated: #{updated_count}"
      puts "Files skipped: #{skipped_count}"
      puts "Files errored: #{error_count}"
      puts "=" * 40
    end

    private

    def load_manifest
      raise ArgumentError, "Manifest not found: #{@manifest_path}" unless File.exist?(@manifest_path)

      YAML.safe_load(File.read(@manifest_path))
    end

    def download_entry_media(entry, media)
      downloaded = {}

      # Podcast URL
      if entry["podcast_url"] && !entry["podcast_url"].empty?
        filename = "#{entry['slug']}.mp3"
        result = media.download_audio_file(entry["podcast_url"], filename)
        downloaded[:audio] = "/media/audio/#{filename}" if result
      end

      # Video URL
      if entry["video_url"] && !entry["video_url"].empty?
        filename = "#{entry['slug']}.mp4"
        result = media.download_file(entry["video_url"], File.join(@output_root, "media", "video", filename))
        downloaded[:video] = "/media/video/#{filename}" if result
      end

      # Captions URL
      if entry["captions_url"] && !entry["captions_url"].empty?
        filename = "#{entry['slug']}.en.vtt"
        result = media.download_captions_file(entry["captions_url"], filename)
        downloaded[:captions] = "/media/captions/#{filename}" if result
      end

      downloaded
    end

    def patch_frontmatter(md_path, downloaded)
      content = File.read(md_path)

      unless content =~ /\A---\s*\n(.*?)\n---/m
        puts "  Warning: No frontmatter found in #{md_path}" if @verbose
        return
      end

      fm_block = $1
      rest = $'

      downloaded.each do |key, value|
        field_name = key.to_s
        if fm_block =~ /^#{field_name}:/
          fm_block = fm_block.sub(/^#{field_name}:.*/, "#{field_name}: \"#{value}\"")
        else
          fm_block += "\n#{field_name}: \"#{value}\""
        end
      end

      new_content = "---\n#{fm_block}\n---#{rest}"
      File.write(md_path, new_content)

      puts "  ✓ Patched: #{md_path}" if @verbose
    end
  end
end

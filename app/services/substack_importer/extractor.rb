# frozen_string_literal: true

module SubstackImporter
  class Extractor
    attr_reader :input_path, :extract_path

    def initialize(input_path, extract_path: nil)
      @input_path = input_path
      @extract_path = extract_path
    end

    def extract
      if zip_file?
        extract_zip
      elsif directory?
        @input_path
      else
        raise ArgumentError, "Input must be a ZIP file or directory: #{@input_path}"
      end
    end

    def cleanup
      FileUtils.rm_rf(@extract_path) if @extract_path && Dir.exist?(@extract_path)
    end

    def posts_dir
      extract_dir = extract

      # First try the standard posts/ directory
      standard_dir = File.join(extract_dir, "posts")
      return standard_dir if Dir.exist?(standard_dir)

      # Otherwise just use the extract root (files might be flat)
      extract_dir
    end

    def csv_path
      # Look for posts.csv or any CSV that starts with "posts"
      extract_dir = extract

      # First try the standard name
      standard_path = File.join(extract_dir, "posts.csv")
      return standard_path if File.exist?(standard_path)

      # Otherwise find any CSV that looks like posts data
      Dir.glob(File.join(extract_dir, "*.csv")).find do |f|
        File.basename(f).include?("posts") || File.basename(f).include?("post")
      end || standard_path  # Return standard path even if not found (will fail gracefully later)
    end

    private

    def zip_file?
      File.file?(@input_path) && @input_path.end_with?(".zip")
    end

    def directory?
      Dir.exist?(@input_path)
    end

    def extract_zip
      # Use provided extract_path or create temp dir
      @extract_path ||= Dir.mktmpdir("substack_import_")

      # Ensure extract_path is absolute and clean
      @extract_path = File.expand_path(@extract_path)

      Rails.logger.info "[SubstackImporter] Extracting to: #{@extract_path}"
      Rails.logger.info "[SubstackImporter] Current working directory: #{Dir.pwd}"

      Zip::File.open(@input_path) do |zip|
        zip.each do |entry|
          entry_name = entry.name.to_s
          Rails.logger.debug "[SubstackImporter] Processing ZIP entry: #{entry_name.inspect}"

          # Skip directories
          if entry.directory?
            Rails.logger.debug "[SubstackImporter] Skipping directory entry: #{entry_name}"
            next
          end

          # Get the clean entry name - extract just the filename portion
          # The entry might have path separators, so we need to handle those
          clean_name = entry_name.gsub(/\\/, "/")  # Normalize backslashes

          # If it looks like an absolute path, extract just the basename
          if clean_name.start_with?("/") || clean_name.match?(/^[a-zA-Z]:/)
            clean_name = File.basename(clean_name)
            Rails.logger.info "[SubstackImporter] Extracted basename from absolute path: #{clean_name}"
          else
            # For relative paths, still extract just the filename to avoid subdirectories
            clean_name = File.basename(clean_name)
            Rails.logger.debug "[SubstackImporter] Using basename: #{clean_name}"
          end

          next if clean_name.empty?

          dest = File.join(@extract_path, clean_name)
          Rails.logger.info "[SubstackImporter] Will extract to: #{dest}"

          # Create the directory
          FileUtils.mkdir_p(@extract_path)

          # Extract using get_input_stream to avoid rubyzip's path interpretation
          File.open(dest, "wb") do |f|
            entry.get_input_stream do |stream|
              f.write(stream.read)
            end
          end

          Rails.logger.info "[SubstackImporter] Successfully extracted: #{clean_name}"
        end
      end

      @extract_path
    end
  end
end

# frozen_string_literal: true

module SubstackImporter
  class Extractor
    attr_reader :input_path, :temp_dir

    def initialize(input_path)
      @input_path = input_path
      @temp_dir = nil
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
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    def posts_dir
      File.join(extract, "posts")
    end

    def csv_path
      File.join(extract, "posts.csv")
    end

    private

    def zip_file?
      File.file?(@input_path) && @input_path.end_with?(".zip")
    end

    def directory?
      Dir.exist?(@input_path)
    end

    def extract_zip
      @temp_dir = Dir.mktmpdir("substack_import_")

      Zip::File.open(@input_path) do |zip|
        zip.each do |entry|
          dest = File.join(@temp_dir, entry.name)
          FileUtils.mkdir_p(File.dirname(dest))
          entry.extract(dest)
        end
      end

      @temp_dir
    end
  end
end

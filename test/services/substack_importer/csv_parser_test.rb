# frozen_string_literal: true

require "test_helper"

module SubstackImporter
  class CsvParserTest < ActiveSupport::TestCase
    def setup
      @tmp_dir = Dir.mktmpdir("csv_parser_test")
      @csv_path = File.join(@tmp_dir, "posts.csv")
    end

    def teardown
      FileUtils.rm_rf(@tmp_dir)
    end

    def test_parse_published_posts
      write_csv([
        { "post_id" => "123.my-post", "title" => "My Post", "is_published" => "true", "post_date" => "2024-01-01" },
      ])

      parser = CsvParser.new(@csv_path)
      posts = parser.parse

      assert_equal 1, posts.count
      assert posts.first.is_published
    end

    def test_parse_drafts
      write_csv([
        { "post_id" => "456.my-draft", "title" => "My Draft", "is_published" => "false", "post_date" => "" },
      ])

      parser = CsvParser.new(@csv_path)
      posts = parser.parse

      assert_equal 1, posts.count
      assert_equal false, posts.first.is_published
    end

    def test_parse_case_insensitive_is_published
      write_csv([
        { "post_id" => "1.p1", "title" => "Upper TRUE", "is_published" => "TRUE", "post_date" => "2024-01-01" },
        { "post_id" => "2.p2", "title" => "Upper FALSE", "is_published" => "FALSE", "post_date" => "" },
        { "post_id" => "3.p3", "title" => "Mixed True", "is_published" => "True", "post_date" => "2024-01-01" },
      ])

      parser = CsvParser.new(@csv_path)
      posts = parser.parse

      assert_equal 3, posts.count
      assert posts[0].is_published, "Upper TRUE should be published"
      assert_equal false, posts[1].is_published, "Upper FALSE should be draft"
      assert posts[2].is_published, "Mixed True should be published"
    end

    def test_filter_excludes_drafts_by_default
      write_csv([
        { "post_id" => "1.pub", "title" => "Published", "is_published" => "true", "post_date" => "2024-01-01" },
        { "post_id" => "2.draft", "title" => "Draft", "is_published" => "false", "post_date" => "" },
      ])

      parser = CsvParser.new(@csv_path)
      parser.parse
      filtered = parser.filter

      assert_equal 1, filtered.count
      assert_equal "Published", filtered.first.title
    end

    def test_filter_includes_drafts_when_option_is_true
      write_csv([
        { "post_id" => "1.pub", "title" => "Published", "is_published" => "true", "post_date" => "2024-01-01" },
        { "post_id" => "2.draft", "title" => "Draft", "is_published" => "false", "post_date" => "" },
      ])

      parser = CsvParser.new(@csv_path)
      parser.parse
      filtered = parser.filter(drafts: true)

      assert_equal 2, filtered.count
    end

    def test_filter_includes_drafts_when_option_is_string_one
      # The UI checkbox sends "1" for checked values.
      write_csv([
        { "post_id" => "1.pub", "title" => "Published", "is_published" => "true", "post_date" => "2024-01-01" },
        { "post_id" => "2.draft", "title" => "Draft", "is_published" => "false", "post_date" => "" },
      ])

      parser = CsvParser.new(@csv_path)
      parser.parse
      filtered = parser.filter(drafts: "1")

      assert_equal 2, filtered.count, "Drafts should be included when option is '1'"
    end

    def test_summary_counts_drafts
      write_csv([
        { "post_id" => "1.pub", "title" => "Published", "is_published" => "true", "post_date" => "2024-01-01" },
        { "post_id" => "2.draft", "title" => "Draft", "is_published" => "false", "post_date" => "" },
      ])

      parser = CsvParser.new(@csv_path)
      parser.parse

      summary = parser.summary
      assert_match(/1 published/, summary)
      assert_match(/1 drafts/, summary)
    end

    private

    def write_csv(rows)
      headers = rows.first.keys
      CSV.open(@csv_path, "w") do |csv|
        csv << headers
        rows.each { |row| csv << headers.map { |h| row[h] } }
      end
    end
  end
end

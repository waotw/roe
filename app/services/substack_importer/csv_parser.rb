# frozen_string_literal: true

module SubstackImporter
  class CsvParser
    attr_reader :posts

    def initialize(csv_path)
      @csv_path = csv_path
      @posts = []
    end

    def parse
      raise ArgumentError, "CSV file not found: #{@csv_path}" unless File.exist?(@csv_path)

      CSV.foreach(@csv_path, headers: true) do |row|
        post_id = row["post_id"].to_s
        id, slug = split_post_id(post_id)

        @posts << Post.new(
          id: id,
          slug: slug,
          title: title_or_fallback(row["title"], slug),
          subtitle: row["subtitle"].to_s,
          date: parse_date(row["post_date"]),
          type: row["type"].to_s,
          audience: row["audience"].to_s,
          is_published: truthy?(row["is_published"]),
          email_sent_at: parse_date(row["email_sent_at"]),
          inbox_sent_at: parse_date(row["inbox_sent_at"]),
          podcast_url: row["podcast_url"].to_s
        )
      end

      @posts
    end

    def filter(options = {})
      filtered = @posts.dup

      # Handle drafts - only include drafts if explicitly requested
      unless truthy?(options[:drafts])
        filtered = filtered.select(&:is_published)
      end

      # Filter by type if specified
      if options[:type].present?
        filtered = filtered.select { |p| p.type == options[:type] }
      end

      # Filter by before date if specified
      if options[:before].present?
        begin
          before_date = Date.parse(options[:before].to_s)
          filtered = filtered.select { |p| p.date && Date.parse(p.date.to_s) < before_date }
        rescue ArgumentError => e
          Rails.logger.warn "[SubstackImporter] Invalid before date: #{options[:before]}"
        end
      end

      # Filter by after date if specified
      if options[:after].present?
        begin
          after_date = Date.parse(options[:after].to_s)
          filtered = filtered.select { |p| p.date && Date.parse(p.date.to_s) > after_date }
        rescue ArgumentError => e
          Rails.logger.warn "[SubstackImporter] Invalid after date: #{options[:after]}"
        end
      end

      filtered
    end

    def summary
      grouped = @posts.group_by(&:type)
      lines = [ "\nCSV Summary:" ]
      grouped.each do |type, posts|
        published = posts.count(&:is_published)
        drafts = posts.count { |p| !p.is_published }
        lines << "  #{type}: #{posts.count} total (#{published} published, #{drafts} drafts)"
      end
      lines << "  Total: #{@posts.count}"
      lines.join("\n")
    end

    private

    def split_post_id(post_id)
      if post_id.include?(".")
        parts = post_id.split(".", 2)
        [ parts[0], parts[1] ]
      else
        [ post_id, "" ]
      end
    end

    # Substack sometimes exports an empty `title` column for drafts. Fall
    # back to a readable title derived from the post_id slug (the part after
    # the dot, e.g. "a-new-metaphysics-of-being-4") so drafts don't import
    # untitled. Hyphens become spaces and each word is capitalized — good
    # enough for a draft the author will likely rename anyway.
    def title_or_fallback(raw_title, slug)
      title = raw_title.to_s.strip
      return title unless title.empty?

      slug.to_s.split("-").reject(&:empty?).map(&:capitalize).join(" ")
    end

    def parse_date(value)
      return nil if value.nil? || value.to_s.strip.empty?

      value.to_s
    end

    # Convert a string-ish value to a boolean using Rails's built-in caster.
    # Handles "1", "true", "TRUE", "yes", true, 1, etc. as truthy and
    # everything else (including nil, "", "false", "FALSE", "0", 0) as falsey.
    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end
  end
end

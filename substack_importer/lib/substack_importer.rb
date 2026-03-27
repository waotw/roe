# frozen_string_literal: true

require "csv"
require "json"
require "yaml"
require "fileutils"
require "date"
require "time"
require "net/http"
require "uri"
require "nokogiri"
require "zip"

module SubstackImporter
  VERSION = "0.1.0"

  Post = Struct.new(
    :id, :slug, :title, :subtitle, :date, :type, :audience,
    :is_published, :email_sent_at, :inbox_sent_at, :podcast_url,
    :html_path, :html_content,
    :cover_image, :podcast_duration, :podcast_episode_number,
    :podcast_season_number, :podcast_episode_type,
    :podcast_episode_image_url, :video_mux_playback_id,
    :transcription_url, :caption_urls, :extracted_audio,
    keyword_init: true
  )
end

require_relative "substack_importer/extractor"
require_relative "substack_importer/csv_parser"
require_relative "substack_importer/html_loader"
require_relative "substack_importer/converter"
require_relative "substack_importer/live_fetcher"
require_relative "substack_importer/media"
require_relative "substack_importer/frontmatter"
require_relative "substack_importer/writer"
require_relative "substack_importer/importer"
require_relative "substack_importer/manifest_downloader"

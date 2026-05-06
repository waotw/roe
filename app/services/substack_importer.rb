# frozen_string_literal: true

require "csv"
require "zip"

module SubstackImporter
  VERSION = "0.1.0"

  before_action :require_development_features

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

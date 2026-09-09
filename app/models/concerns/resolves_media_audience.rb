# frozen_string_literal: true

# Which files a paid record actually keeps behind the paywall.
#
# A record's own audience isn't the answer for every file it references. Two
# things a paid post or page shows to everyone:
#
#   the featured image — rendered in the header above the paywall, and published
#     by Roe itself as og:image and in collection listings. Returning 403 for a
#     URL we advertise isn't protection, it's a broken page and a broken social
#     card.
#   anything above the paywall — a free video with the article gated after it is
#     a normal shape, and the whole point of choosing where the block goes.
#
# audio, video and captions in metadata stay protected. On a paid episode those
# ARE the paid thing, so exempting metadata wholesale would hand them to anyone
# with the URL.
module ResolvesMediaAudience
  extend ActiveSupport::Concern

  # Metadata fields Roe displays regardless of the record's audience.
  PUBLIC_MEDIA_FIELDS = %w[image social_image].freeze

  # The audience of ONE file this record references, which is not always the
  # record's own.
  def media_audience_for(path)
    path = path.to_s
    return "free" if publicly_shown_media?(path)
    return "free" if MediaPaths.above_paywall(content).include?(path)

    media_audience
  end

  private

  def publicly_shown_media?(path)
    PUBLIC_MEDIA_FIELDS.any? { |field| metadata[field].to_s.strip == path }
  end
end

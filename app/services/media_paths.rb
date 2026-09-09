# frozen_string_literal: true

# Where /media/ paths appear in a piece of content, and which side of a paywall
# they fall on.
#
# Extracted so the usage index and the audience calculation ask one question one
# way. They previously scanned independently, which is how a file could be
# indexed as referenced by a post and yet classified as though it weren't.
module MediaPaths
  MEDIA_PATH = %r{/media/[\w./\-]+}

  # The paywall block, in source markdown rather than rendered HTML. Rendering
  # emits <!-- PAID_CONTENT_GATE --> (see feed_generator), but recomputing
  # audience can't afford to render every post to find it.
  #
  # `for:` and `type:` are both accepted by roeanji_kind, so both appear here.
  PAYWALL_FENCE = /^ {0,3}(`{3,}|~{3,})\s*form\b[^\n]*\n(?:(?!\1)[^\n]*\n)*?\s*(?:for|type):\s*paid_content\b.*?^ {0,3}\1\s*$/m

  module_function

  def in(text)
    return [] if text.blank?

    text = text.to_s
    paths = []
    paths.concat text.scan(/\]\((\/media\/[^)]+)\)/).flatten
    paths.concat text.scan(/(?:src|href)\s*=\s*["'](\/media\/[^"']+)["']/i).flatten
    paths.concat text.scan(MEDIA_PATH)
    paths.uniq
  end

  # Paths appearing before the paywall — the part a signed-out reader sees.
  #
  # Fails closed. No paywall block means no free preview, matching what the feed
  # already does: "when the post has no gate there's nothing free to show." A
  # regex that failed to match would otherwise quietly publish a whole article's
  # media.
  def above_paywall(text)
    text = text.to_s
    return [] unless text.match?(PAYWALL_FENCE)

    self.in(text.split(PAYWALL_FENCE, 2).first)
  end
end

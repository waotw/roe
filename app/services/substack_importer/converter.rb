# frozen_string_literal: true

module SubstackImporter
  class Converter
    def initialize(verbose: false, insert_paywalls: true, paywall_text: nil, paywall_button_text: nil)
      @verbose = verbose
      @images = []
      @footnotes = {}
      @insert_paywalls = insert_paywalls
      @paywall_text = paywall_text || "Upgrade to continue reading."
      @paywall_button_text = paywall_button_text || "Become a paid member"
    end

    def convert(html)
      return "" if html.nil? || html.empty?

      @images = []
      @footnotes = {}

      doc = Nokogiri::HTML.fragment(html)

      collect_footnotes(doc)
      remove_footnote_divs(doc)

      markdown = process_node(doc)
      markdown = cleanup(markdown)

      # Append footnote definitions
      unless @footnotes.empty?
        definitions = render_footnote_definitions
        markdown = "#{markdown}\n\n#{definitions}" unless definitions.empty?
      end

      markdown.strip
    end

    def collected_images
      @images
    end

    private

    def collect_footnotes(doc)
      doc.css("div.footnote").each do |footnote_div|
        number_el = footnote_div.at_css("a.footnote-number")
        content_el = footnote_div.at_css("div.footnote-content")

        next unless number_el && content_el

        fn_id = number_el["id"].to_s
        fn_number = number_el.inner_text.strip

        # Convert footnote content HTML to markdown
        # Process each child element to preserve structure
        raw_markdown = process_node(content_el).strip
        # Normalize: collapse excessive newlines
        fn_markdown = raw_markdown.gsub(/\n{3,}/, "\n\n").strip

        @footnotes[fn_id] = { number: fn_number, markdown: fn_markdown }
      end
    end

    def render_footnote_definitions
      @footnotes.map do |_fn_id, fn|
        number = fn[:number]
        markdown = fn[:markdown]

        # Indent continuation lines with 4 spaces for markdown footnotes
        lines = markdown.split("\n")
        if lines.length == 1
          "[^#{number}]: #{lines.first}"
        else
          first = "[^#{number}]: #{lines.first}"
          rest = lines[1..].map { |line| "    #{line}" }
          ([ first ] + rest).join("\n")
        end
      end.join("\n\n")
    end

    def remove_footnote_divs(doc)
      doc.css("div.footnote").each(&:remove)
    end

    def process_node(node, depth: 0)
      return "" if node.nil?

      case node
      when Nokogiri::XML::DocumentFragment, Nokogiri::XML::Element
        process_element(node, depth: depth)
      when Nokogiri::XML::Text
        node.text
      when Nokogiri::XML::NodeSet
        node.map { |child| process_node(child, depth: depth) }.join
      else
        ""
      end
    end

    def process_element(node, depth: 0)
      tag = node.name.downcase

      # Check for Substack-specific elements first
      result = process_substack_element(node)
      return result if result

      case tag
      when "h1" then "# #{inner_text(node)}\n\n"
      when "h2" then "## #{inner_text(node)}\n\n"
      when "h3" then "### #{inner_text(node)}\n\n"
      when "h4" then "#### #{inner_text(node)}\n\n"
      when "h5" then "##### #{inner_text(node)}\n\n"
      when "h6" then "###### #{inner_text(node)}\n\n"
      when "p"
        text = process_children(node, depth: depth).strip
        text.empty? ? "" : "#{text}\n\n"
      when "br" then "\n"
      when "strong", "b"
        wrap_emphasis(process_children(node, depth: depth), "**")
      when "em", "i"
        wrap_emphasis(process_children(node, depth: depth), "*")
      when "s"
        wrap_emphasis(process_children(node, depth: depth), "~~")
      when "a"
        process_link(node, depth: depth)
      when "ul"
        process_list(node, ordered: false, depth: depth)
      when "ol"
        process_list(node, ordered: true, depth: depth)
      when "li"
        process_children(node, depth: depth)
      when "blockquote"
        process_blockquote(node, depth: depth)
      when "pre"
        process_code_block(node)
      when "code"
        if node.parent&.name&.downcase == "pre"
          process_children(node, depth: depth)
        else
          "`#{inner_text(node)}`"
        end
      when "hr" then "---\n\n"
      when "img"
        process_image(node)
      when "figure"
        process_figure(node)
      when "figcaption"
        ""
      when "div", "span", "section", "article", "picture", "source"
        process_children(node, depth: depth)
      when "script", "style", "noscript"
        ""
      else
        process_children(node, depth: depth)
      end
    end

    def process_substack_element(node)
      component = node["data-component-name"]
      class_list = node["class"].to_s

      # Captioned image container
      if class_list.include?("captioned-image-container")
        return process_captioned_image(node)
      end

      # Image gallery
      if class_list.include?("image-gallery-embed")
        return process_image_gallery(node)
      end

      # Audio embed
      if component == "AudioPlaceholder" || class_list.include?("native-audio-embed")
        return process_audio_embed(node)
      end

      # Video embed
      if component == "VideoPlaceholder" || class_list.include?("native-video-embed")
        return process_video_embed(node)
      end

      # LaTeX
      if component == "LatexBlockToDOM" || class_list.include?("latex-rendered")
        return process_latex(node)
      end

      # Preformatted/poetry
      if component == "PreformattedTextBlockToDOM" || class_list.include?("preformatted-block")
        return process_preformatted(node)
      end

      # Pull quote
      if class_list.include?("pullquote")
        return process_pullquote(node)
      end

      # Button
      if component == "ButtonCreateButton" || class_list.include?("button-wrapper")
        return process_button(node)
      end

      # Captioned button
      if component == "CaptionedButtonToDOM" || class_list.include?("captioned-button-wrap")
        return process_captioned_button(node)
      end

      # Subscribe widget
      if component == "SubscribeWidgetToDOM" || class_list.include?("subscription-widget-wrap-editor")
        return process_subscribe_widget(node)
      end

      # Footnote anchor
      if component == "FootnoteAnchorToDOM" || class_list.include?("footnote-anchor")
        return process_footnote_anchor(node)
      end

      # Paywall
      if class_list.include?("paywall-jump")
        return @insert_paywalls ? paywall_block : "<!--substack members-only-->\n\n"
      end

      # Tweet embeds (stub)
      if class_list.include?("tweet")
        return process_tweet_embed(node)
      end

      # Embedded posts (stub)
      if class_list.include?("embedded-post-wrap")
        return process_embedded_post(node)
      end

      # Digest post embed (post links)
      if class_list.include?("digest-post-embed")
        return process_digest_embed(node)
      end

      # Polls (stub)
      if class_list.include?("poll-embed")
        return ""
      end

      # Comments (stub)
      if class_list.include?("comment")
        return ""
      end

      nil
    end

    def process_captioned_image(node)
      img = node.at_css("img[data-attrs]")
      return "" unless img

      data = parse_data_attrs(img["data-attrs"])
      return "" unless data

      src = data["src"].to_s
      alt = data["alt"].to_s.strip
      caption_node = node.at_css("figcaption.image-caption")
      caption = caption_node ? caption_node.inner_text.strip : ""

      @images << { src: src, alt: alt }

      if caption.empty?
        "![#{alt}](#{src})\n\n"
      else
        "![#{alt}](#{src})(*#{caption}*)\n\n"
      end
    end

    def process_image_gallery(node)
      data = parse_data_attrs(node["data-attrs"])
      return "" unless data

      gallery = data["gallery"] || {}
      images = gallery["images"] || []
      caption = gallery["caption"].to_s

      lines = images.each_with_index.map do |img, i|
        src = img["src"].to_s
        alt = (img["alt"].to_s.presence || data["alt"].to_s).strip

        @images << { src: src, alt: alt }

        if i == 0 && !caption.empty?
          "![#{alt}](#{src})(*#{caption}*)"
        else
          "![#{alt}](#{src})"
        end
      end

      "#{lines.join("\n")}\n\n"
    end

    def process_audio_embed(node)
      data = parse_data_attrs(node["data-attrs"]) || {}
      media_id = data["mediaUploadId"].to_s
      duration = data["duration"]
      downloadable = data["downloadable"] || false

      duration_str = duration ? "#{duration}s" : "unknown"

      "[AUDIO: mediaUploadId=#{media_id}, duration=#{duration_str}, downloadable=#{downloadable}]\n\n"
    end

    def process_video_embed(node)
      data = parse_data_attrs(node["data-attrs"]) || {}
      media_id = data["mediaUploadId"].to_s

      "[VIDEO: mediaUploadId=#{media_id}]\n\n"
    end

    def process_latex(node)
      data = parse_data_attrs(node["data-attrs"]) || {}
      expression = data["persistentExpression"].to_s

      "$$ #{expression} $$\n\n"
    end

    def process_preformatted(node)
      pre = node.at_css("pre.text") || node.at_css("pre")
      return "" unless pre

      # Walk the pre's children preserving whitespace EXACTLY (no strip,
      # no newline collapse) while still converting inline emphasis tags
      # to markdown. Substack lets writers bold/italicize inside poetry
      # blocks; the regular process_node would either strip the tags
      # (inner_text) or normalize the surrounding whitespace.
      text = preformatted_inline(pre)

      "```poetry\n#{text}\n```\n\n"
    end

    # Whitespace-preserving sibling of process_node, used only inside
    # preformatted/poetry blocks. Converts inline tags to markdown but
    # never strips text nodes.
    def preformatted_inline(node)
      node.children.map do |child|
        case child
        when Nokogiri::XML::Text
          child.text
        when Nokogiri::XML::Element
          case child.name.downcase
          when "strong", "b"
            wrap_emphasis(preformatted_inline(child), "**")
          when "em", "i"
            wrap_emphasis(preformatted_inline(child), "*")
          when "s"
            wrap_emphasis(preformatted_inline(child), "~~")
          when "br"
            "\n"
          when "a"
            href = child["href"].to_s
            text = preformatted_inline(child)
            href.empty? ? text : "[#{text}](#{href})"
          else
            preformatted_inline(child)
          end
        else
          ""
        end
      end.join
    end

    def process_pullquote(node)
      text_el = node.at_css("p")
      cite_el = node.at_css("cite")

      text = text_el ? text_el.inner_text.strip : ""
      attribution = cite_el ? cite_el.inner_text.strip : ""

      lines = [ "card", "type: pullquote", "text: #{text}" ]
      lines << "attribution: #{attribution}" unless attribution.empty?

      "```#{lines.join("\n")}\n```\n\n"
    end

    def process_button(node)
      data = parse_data_attrs(node["data-attrs"]) || {}
      url = data["url"].to_s
      text = data["text"].to_s

      if text.downcase.include?("subscribe")
        "[SUBSCRIBE](#{url})\n\n"
      else
        "[BUTTON: #{text}](#{url})\n\n"
      end
    end

    def process_captioned_button(node)
      caption_el = node.at_css("p.cta-caption")
      button_el = node.at_css("p.button-wrapper")

      parts = []

      if caption_el
        caption_text = caption_el.inner_text.strip
        parts << caption_text unless caption_text.empty?
      end

      if button_el
        data = parse_data_attrs(button_el["data-attrs"]) || {}
        url = data["url"].to_s
        text = data["text"].to_s

        if text.downcase.include?("subscribe")
          parts << "[SUBSCRIBE](#{url})"
        else
          parts << "[BUTTON: #{text}](#{url})"
        end
      end

      "#{parts.join("\n")}\n\n"
    end

    def process_subscribe_widget(node)
      data = parse_data_attrs(node["data-attrs"]) || {}
      url = data["url"].to_s

      "[SUBSCRIBE](#{url})\n\n"
    end

    def process_footnote_anchor(node)
      href = node["href"].to_s.sub("#", "")
      fn = @footnotes[href]

      if fn
        "[^#{fn[:number]}]"
      else
        "[^?]"
      end
    end

    def process_tweet_embed(node)
      # Try to find tweet URL from blockquote or data attributes
      url = node["data-url"] || node.at_css("a")&.[]("href") || ""
      text = node.at_css("p")&.inner_text&.strip || ""

      if text.empty?
        "> Tweet: #{url}\n\n"
      else
        "> #{text}\n> — #{url}\n\n"
      end
    end

    def process_embedded_post(node)
      # Extract post info for card syntax
      title = node.at_css("h3, h4, .post-title")&.inner_text&.strip || ""
      excerpt = node.at_css("p, .post-excerpt")&.inner_text&.strip || ""
      image = node.at_css("img")&.[]("src") || ""
      post_slug = node["data-post-id"] || ""

      lines = [ "card", "type: post-link" ]
      lines << "text: #{excerpt}" unless excerpt.empty?
      lines << "image: #{image}" unless image.empty?
      lines << "post: #{post_slug}" unless post_slug.empty?

      # Check for embed size in CSS classes
      class_list = node["class"].to_s.downcase
      style = if class_list.include?("small") || class_list.include?("compact")
        "small"
      elsif class_list.include?("large") || class_list.include?("full")
        "large"
      else
        "medium"
      end
      lines << "style: #{style}"

      "```#{lines.join("\n")}\n```\n\n"
    end

    def process_digest_embed(node)
      data = parse_data_attrs(node["data-attrs"])
      return "" unless data

      canonical_url = data["canonical_url"].to_s

      # Extract slug from canonical URL
      slug = canonical_url.split("/").last.to_s

      lines = [ "card", "type: post-link" ]
      lines << "post: #{slug}" unless slug.empty?

      # Check for embed size in data-attrs (size field like "lg", "md", "sm")
      embed_size = data["size"].to_s.downcase

      # If not in size field, check display field
      if embed_size.empty?
        embed_size = data["display"].to_s.downcase
      end

      # If not in data, check for size-related classes
      if embed_size.empty?
        class_list = node["class"].to_s.downcase
        if class_list.include?("small") || class_list.include?("compact")
          embed_size = "small"
        elsif class_list.include?("large") || class_list.include?("full")
          embed_size = "large"
        elsif class_list.include?("medium") || class_list.include?("standard")
          embed_size = "medium"
        end
      end

      # Map Substack size abbreviations to your system
      style = case embed_size
      when "sm", "small", "compact"
        "small"
      when "lg", "large", "full"
        "large"
      when "md", "medium", "standard", ""
        "medium"
      else
        "medium"
      end

      lines << "style: #{style}"

      "```#{lines.join("\n")}\n```\n\n"
    end

    def process_link(node, depth: 0)
      href = node["href"].to_s
      text = process_children(node, depth: depth).strip

      return href if text.empty?
      return text if href.empty?

      "[#{text}](#{href})"
    end

    def process_list(node, ordered:, depth:)
      items = node.css("> li")
      lines = items.each_with_index.map do |li, i|
        prefix = ordered ? "#{i + 1}." : "-"
        content = process_children(li, depth: depth + 1).strip
        "#{prefix} #{content}"
      end

      "#{lines.join("\n")}\n\n"
    end

    def process_blockquote(node, depth: 0)
      text = process_children(node, depth: depth).strip
      quoted = text.split("\n").map { |line| "> #{line}" }.join("\n")

      "#{quoted}\n\n"
    end

    def process_code_block(node)
      code = node.at_css("code")
      lang = ""

      if code
        classes = code["class"].to_s
        lang_match = classes.match(/language-(\w+)/)
        lang = lang_match[1] if lang_match
        text = code.inner_text
      else
        text = node.inner_text
      end

      "```#{lang}\n#{text}\n```\n\n"
    end

    def process_image(node)
      data = parse_data_attrs(node["data-attrs"])
      if data
        src = data["src"].to_s
        alt = data["alt"].to_s.strip
      else
        src = node["src"].to_s
        alt = node["alt"].to_s.strip
      end

      return "" if src.empty?

      @images << { src: src, alt: alt }

      "![#{alt}](#{src})\n\n"
    end

    def process_figure(node)
      img = node.at_css("img")
      figcaption = node.at_css("figcaption")

      parts = []

      if img
        parts << process_image(img)
      end

      if figcaption
        caption = figcaption.inner_text.strip
        parts << caption unless caption.empty?
      end

      "#{parts.join("\n\n")}\n\n"
    end

    def process_children(node, depth: 0)
      node.children.map { |child| process_node(child, depth: depth) }.join
    end

    def inner_text(node)
      node.inner_text.strip
    end

    # Wrap inline emphasis content (bold/italic/strikethrough) so that any
    # leading or trailing spaces/tabs end up *outside* the markdown
    # delimiters. Substack often produces e.g. `<strong>foo </strong>`,
    # which would naively become `**foo **` — and CommonMark rejects that
    # as bold because the closing `**` is preceded by whitespace. Moving
    # the space outside (`**foo** `) renders correctly.
    # Restricted to spaces/tabs (not all whitespace) so multi-line content
    # isn't reflowed across newlines.
    def wrap_emphasis(text, marker)
      return "" if text.nil?
      return text if text.strip.empty?
      leading = text[/\A[ \t]*/]
      trailing = text[/[ \t]*\z/]
      "#{leading}#{marker}#{text.strip}#{marker}#{trailing}"
    end

    def parse_data_attrs(json_string)
      return nil if json_string.nil? || json_string.empty?

      JSON.parse(json_string)
    rescue JSON::ParserError
      nil
    end

    def paywall_block
      <<~PAYWALL
        ```form
        for: paid_content
        text: #{@paywall_text}
        button-text: #{@paywall_button_text}
        ```

      PAYWALL
    end

    def cleanup(text)
      text
        .gsub(/\n{3,}/, "\n\n")
        .gsub(/ +\n/, "\n")
        .strip
    end
  end
end

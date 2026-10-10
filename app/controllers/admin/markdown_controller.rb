# Markdown diagnostics for the editor, shared by posts, pages, products and
# emails — they all render shared/_editor, so a per-resource endpoint would be
# four copies of the same thing.
#
# Content arrives in the request body rather than being read from disk: the
# editor lints what's in the textarea, which hasn't been saved yet.
#
# The rules live in MarkdownDoctor and are never reimplemented in JavaScript.
# Two copies of "what counts as a problem" would disagree, and the CLI, the
# editor, and any future check would drift apart.
class Admin::MarkdownController < Admin::BaseController
  # POST /admin/markdown/check
  # → { issues: [{ type:, line:, message:, fixable:, label: }], fixable_count: }
  def check
    issues = MarkdownDoctor.diagnose(content_param)

    render json: {
      issues: issues.map { |i| present(i) },
      fixable_count: issues.count { |i| i[:fixable] }
    }
  end

  # POST /admin/markdown/fix
  # → { content:, applied: [...], remaining: [...] }
  #
  # Re-lints the content it's given rather than trusting an earlier check, so a
  # fix can't be applied to a document the writer has since edited. Only
  # MarkdownDoctor::FIXABLE_TYPES are touched; everything else comes back in
  # `remaining` for the writer to decide about.
  def fix
    fixed, applied = MarkdownDoctor.fix(content_param)

    render json: {
      content: fixed,
      applied: applied.map { |i| present(i) },
      remaining: MarkdownDoctor.diagnose(fixed).map { |i| present(i) }
    }
  end

  # POST /admin/markdown/blocks
  # → { blocks: [{ warnings: [{ title:, message:, html: }] }, ...] } — one entry
  # per block sent, in the same order.
  #
  # The live editor draws each Roe-anji block as a labelled card, and swaps the
  # card for the parser's own warning when the block won't render. Rather than
  # teach JavaScript what a broken collection looks like, each block goes
  # through the real renderer in preview mode — the mode that shows warnings —
  # and whatever amber boxes come out are handed back, HTML and all, so the
  # editor shows exactly the box the preview would. One renderer, one set of
  # rules, so the editor can't call a block fine that the page then rejects.
  MAX_BLOCKS = 50

  def blocks
    sources = Array(params[:blocks]).first(MAX_BLOCKS).map(&:to_s)

    render json: { blocks: sources.map { |source| { warnings: block_warnings(source) } } }
  end

  private

  # A throwaway Post is only a vehicle for HasMarkdownExtensions: it's never
  # saved, and nothing on it but the content is read.
  def block_warnings(source)
    html = Post.new(content: source).to_html(preview: true).to_s
    Nokogiri::HTML.fragment(html).css("[data-roe-warning]").map do |box|
      title = box.at_css("strong")&.text.to_s.sub(/\A\s*⚠️\s*/, "").strip
      message = box.dup.tap { |copy| copy.at_css("strong")&.remove }.text.squish
      { title: title, message: message, html: box.to_html }
    end
  rescue StandardError => e
    # A block that crashes the renderer is the most broken block there is.
    Rails.logger.warn("[markdown#blocks] #{e.class}: #{e.message}")
    [ { title: "This block couldn't be rendered", message: e.message.to_s.truncate(200), html: nil } ]
  end

  def content_param
    params[:content].to_s
  end

  # ISSUE_TYPES holds the human label; the raw symbol is for grouping and CSS.
  def present(issue)
    issue.slice(:type, :line, :message, :fixable)
         .merge(label: MarkdownDoctor::ISSUE_TYPES[issue[:type]])
  end
end

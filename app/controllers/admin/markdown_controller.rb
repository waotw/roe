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

  private

  def content_param
    params[:content].to_s
  end

  # ISSUE_TYPES holds the human label; the raw symbol is for grouping and CSS.
  def present(issue)
    issue.slice(:type, :line, :message, :fixable)
         .merge(label: MarkdownDoctor::ISSUE_TYPES[issue[:type]])
  end
end

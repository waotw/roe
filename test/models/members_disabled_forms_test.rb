# frozen_string_literal: true

require "test_helper"

# With Members off there is no member to act on and no route to post to, but
# every member form rendered anyway — so a sign-up page looked finished and
# failed on submit, with nothing to say why.
class MembersDisabledFormsTest < ActiveSupport::TestCase
  MEMBER_FORMS = %w[signup signin checkout donate unsubscribe].freeze

  def block(kind) = "```form\nfor: #{kind}\n```\n"

  test "every member form tells the author why it can't render" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    MEMBER_FORMS.each do |kind|
      assert_block_warning block(kind), matching: /Members isn't enabled/
    end
  end

  test "the warning names the form, so a page of blocks says which one" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    assert_match "Sign in form unavailable", render_block(block("signin"), context: :preview)
    assert_match "Sign up form unavailable", render_block(block("signup"), context: :preview)
    assert_match "Donate form unavailable",  render_block(block("donate"), context: :preview)
  end

  # Members off means members.yml doesn't exist yet, so pointing at a setting
  # inside it would send the author looking for a file they haven't got.
  test "the hint points at the button that creates members.yml" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    assert_match "ENABLE MEMBERS", render_block(block("signin"), context: :preview)
  end

  test "a reader gets nothing — not a form whose submit goes nowhere" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    MEMBER_FORMS.each do |kind|
      html = render_block(block(kind), context: :published)

      assert_no_match(/<form/, html, "#{kind} still rendered a form with members off")
      assert_no_match(/⚠️/, html, "#{kind} leaked a warning to a reader")
    end
  end

  # The paywall asks for :payments_configured, not :members, and explains the
  # members case in its own words — the generic warning would talk over it.
  test "the paywall keeps its own explanation" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    html = render_block("```form\nfor: paid_content\n```\n", context: :preview)

    assert_match "no reason for a paywall", html
    assert_no_match(/Members isn't enabled/, html)
  end

  test "with members on, the forms render as before" do
    SiteFeature.stubs(:members_enabled?).returns(true)

    %w[signin signup unsubscribe].each do |kind|
      html = render_block(block(kind), context: :published)

      assert_match(/<form/, html, "#{kind} should render once members is on")
      assert_no_match(/⚠️/, html)
    end
  end
end

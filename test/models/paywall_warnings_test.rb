# frozen_string_literal: true

require "test_helper"

# The Paywall block used to be hidden from the ACTION menu until Stripe was
# connected, so you couldn't build the paid-content flow until after wiring up
# billing — backwards from how a site gets set up. It's available once payments
# are configured; these warnings cover the gap between "configured" and
# "actually able to charge", and the other ways a paywall can be inert.
# These assert that a warning fires and names the thing to fix — never its
# exact wording. The copy is meant to be edited, and a test that pins prose
# fails on a rewrite that changed nothing about the behaviour.
class PaywallWarningsTest < ActiveSupport::TestCase
  BODY = <<~MD
    Free part.

    ```form
    for: paid_content
    text: Members only
    button_text: Upgrade
    ```

    Paid part.
  MD

  def rendered(audience: "paid", preview: true)
    post = Post.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "p.md"),
      content: BODY,
      metadata: { "title" => "P", "url_name" => "p", "status" => "published",
                  "audience" => audience }
    )
    post.to_html(preview: preview)
  end

  def features(members:, payments:)
    SiteFeature.stubs(:members_enabled?).returns(members)
    SiteFeature.stubs(:payments_enabled?).returns(payments)
  end

  test "with everything configured there's no warning" do
    features(members: true, payments: true)

    html = rendered

    assert_includes html, "PAID_CONTENT_GATE"
    assert_not_includes html, "⚠️"
  end

  # The case this was built for: you can write the paywall before Stripe.
  test "payments not connected warns but still renders the gate" do
    features(members: true, payments: false)

    html = rendered

    assert_includes html, "⚠️"
    assert_includes html, "Stripe", "the warning has to name what's not connected"
    assert_includes html, "PAID_CONTENT_GATE", "the gate still works — the preview has to cut here"
  end

  test "members off says the paywall gates nothing" do
    features(members: false, payments: false)

    html = rendered

    assert_includes html, "⚠️"
    assert_includes html, "Members", "the warning has to name what's missing"
  end

  # A paywall on a free post renders a gate that withholds nothing — easy to
  # do by forgetting the metadata, and invisible without this.
  test "a paywall on a post everyone can read is flagged" do
    features(members: true, payments: true)

    html = rendered(audience: "everyone")

    assert_includes html, "⚠️"
    assert_includes html, "audience", "the warning has to name the field to fix"
  end

  # Warnings are for whoever is writing. A reader sees the gate and nothing else.
  test "nothing is warned outside a preview" do
    features(members: true, payments: false)

    html = rendered(preview: false)

    assert_not_includes html, "⚠️"
    assert_includes html, "PAID_CONTENT_GATE"
  end

  # ── The menu gate ──────────────────────────────────────────────────────────

  test "Paywall is offered once payments are configured, without Stripe" do
    kinds = ActionBuilderSchema.form_kinds(members: true, payments: false, payments_configured: true)

    assert_includes kinds.map { |k| k[:value] }, "paid_content"
  end

  # Checkout and Donate are gated on :members and always have been — they've
  # never asked for Stripe keys. Pinned so this stays a deliberate choice
  # rather than something that drifts when the gates are next touched.
  test "the other form kinds are unchanged by the paywall gate" do
    before = ActionBuilderSchema.form_kinds(members: true, payments: true, payments_configured: true)
    after  = ActionBuilderSchema.form_kinds(members: true, payments: false, payments_configured: true)

    assert_equal before.map { |k| k[:value] }, after.map { |k| k[:value] },
      "only the paywall's availability depends on payments_configured"
  end

  test "payments off entirely offers no paywall" do
    kinds = ActionBuilderSchema.form_kinds(members: true, payments: false, payments_configured: false)

    assert_not_includes kinds.map { |k| k[:value] }, "paid_content"
  end
end

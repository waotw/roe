# frozen_string_literal: true

require "test_helper"

# Which imported Substack members are granted paid access. Money-adjacent: a
# wrong answer either hands out paid access nobody bought, or strips it from
# people who did. The three grants widen rather than compete — lifetime only,
# annual as well, or every paid plan — so ticking a broader one covers the
# narrower ones.
class SubstackImporter::MembersImporterTierTest < ActiveSupport::TestCase
  # A subscription that is unambiguously live, so these tests isolate the
  # plan/option matrix from the separate "is it still effective" check.
  ACTIVE = { active_subscription: true }.freeze

  # Import#options reads through configuration["options"].
  def tier_for(plan, options, extra = {})
    import = Import.new(configuration: { "options" => options.transform_keys(&:to_s) })
    importer = SubstackImporter::MembersImporter.new(import)
    importer.send(:determine_tier, ACTIVE.merge(plan: plan).merge(extra))
  end

  # --- nothing ticked ------------------------------------------------------

  test "no options granted means nobody is upgraded" do
    %w[lifetime yearly monthly quarterly semiannually ios_app comp other].each do |plan|
      assert_equal :free, tier_for(plan, {}), "#{plan} should stay free"
    end
  end

  # --- lifetime only -------------------------------------------------------

  test "auto_gift_lifetime upgrades lifetime and nothing else" do
    opts = { auto_gift_lifetime: true }

    assert_equal :paid, tier_for("lifetime", opts)
    %w[yearly monthly quarterly semiannually ios_app].each do |plan|
      assert_equal :free, tier_for(plan, opts), "#{plan} shouldn't be caught by the lifetime grant"
    end
  end

  # --- annual --------------------------------------------------------------

  test "auto_gift_annual upgrades yearly and nothing else" do
    opts = { auto_gift_annual: true }

    assert_equal :paid, tier_for("yearly", opts)
    assert_equal :free, tier_for("lifetime", opts), "annual doesn't imply lifetime"
    %w[monthly quarterly ios_app].each do |plan|
      assert_equal :free, tier_for(plan, opts), "#{plan} isn't annual"
    end
  end

  # semiannually bills twice a year, so it's a recurring plan rather than an
  # annual one — it belongs with monthly, not with yearly.
  test "semiannually is not treated as annual" do
    assert_equal :free, tier_for("semiannually", { auto_gift_annual: true })
    assert_equal :paid, tier_for("semiannually", { auto_gift_paid: true })
  end

  # --- all paid ------------------------------------------------------------

  test "auto_gift_paid upgrades every recurring plan, including yearly" do
    opts = { auto_gift_paid: true }

    %w[monthly quarterly semiannually yearly ios_app].each do |plan|
      assert_equal :paid, tier_for(plan, opts), "#{plan} is a paid plan"
    end
    assert_equal :free, tier_for("lifetime", opts), "lifetime has its own grant"
  end

  # --- the grants combine, they don't conflict -----------------------------

  # The boxes are independent, so any combination is valid — this is the one
  # that grants the two one-off-ish plans without gifting monthly subscribers.
  test "lifetime and annual together upgrade both, and nothing else" do
    opts = { auto_gift_lifetime: true, auto_gift_annual: true }

    assert_equal :paid, tier_for("lifetime", opts)
    assert_equal :paid, tier_for("yearly", opts)
    %w[monthly quarterly semiannually ios_app].each do |plan|
      assert_equal :free, tier_for(plan, opts), "#{plan} shouldn't be swept up"
    end
  end

  test "a broader grant covers a narrower one, in either order" do
    both = { auto_gift_annual: true, auto_gift_paid: true }

    assert_equal :paid, tier_for("yearly", both), "covered twice is still paid"
    assert_equal :paid, tier_for("monthly", both)
  end

  test "all three together upgrade every paying plan" do
    opts = { auto_gift_lifetime: true, auto_gift_annual: true, auto_gift_paid: true }

    %w[lifetime yearly monthly quarterly semiannually ios_app].each do |plan|
      assert_equal :paid, tier_for(plan, opts), "#{plan} should be paid"
    end
    # Comped and unknown plans never bought anything, so they stay free.
    %w[comp other].each do |plan|
      assert_equal :free, tier_for(plan, opts), "#{plan} shouldn't be granted paid"
    end
  end

  test "a member with no plan is free regardless of options" do
    import = Import.new(configuration: { "options" => { "auto_gift_paid" => true, "auto_gift_annual" => true } })
    importer = SubstackImporter::MembersImporter.new(import)

    assert_equal :free, importer.send(:determine_tier, { active_subscription: true })
  end

  # --- a grant still requires a live subscription --------------------------

  # Otherwise a lapsed subscriber imports as paid purely because their plan
  # column still says "yearly".
  test "a lapsed subscription is not upgraded, whichever grant applies" do
    lapsed = { active_subscription: false, expiry: 1.year.ago.iso8601 }

    assert_equal :free, tier_for("yearly", { auto_gift_annual: true }, lapsed)
    assert_equal :free, tier_for("yearly", { auto_gift_paid: true }, lapsed)
    assert_equal :free, tier_for("lifetime", { auto_gift_lifetime: true }, lapsed)
  end

  test "an inactive subscription with a future expiry is still upgraded" do
    winding_down = { active_subscription: false, expiry: 1.month.from_now.iso8601 }

    assert_equal :paid, tier_for("yearly", { auto_gift_annual: true }, winding_down)
  end
end

# frozen_string_literal: true

require "test_helper"

# The deletion-confirmation threshold is the site owner's dial, not a constant
# only a developer can move. Read per-sync so changing it takes effect on the
# next sync rather than the next boot.
class SiteSync::ConfirmDeletionsSettingTest < ActiveSupport::TestCase
  def set(value)
    SiteConfig.stubs(:get).with("sync_confirm_deletions_over").returns(value)
  end

  test "unset falls back to the safe default" do
    [ nil, "", "   " ].each do |blank|
      set(blank)
      assert_equal 0, SiteSync::Reconciler.confirm_deletions_over, "#{blank.inspect} should fall back"
    end
  end

  test "a number is used as written" do
    set("20")
    assert_equal 20, SiteSync::Reconciler.confirm_deletions_over

    set(5)
    assert_equal 5, SiteSync::Reconciler.confirm_deletions_over
  end

  # Blank means "unset". An explicit 0 means "ask every time" — the same answer
  # today, but they'd diverge the moment the default moved, and `to_i` would
  # flatten them into one.
  test "an explicit 0 is a real answer, not a blank" do
    set("0")
    assert_equal 0, SiteSync::Reconciler.confirm_deletions_over
  end

  test "never turns confirmation off" do
    %w[never NEVER off none].each do |word|
      set(word)
      assert_nil SiteSync::Reconciler.confirm_deletions_over, "#{word.inspect} should disable"
    end
  end

  test "nonsense falls back rather than crashing a sync" do
    set("twenty")
    assert_equal 0, SiteSync::Reconciler.confirm_deletions_over
  end

  test "the setting is offered in the Site Sync section of the admin form" do
    fields = Admin::ConfigsController::SITE_CONFIG_SCHEMA[:site_sync][:fields]

    assert_includes fields.keys, "sync_confirm_deletions_over"
    assert_equal "Confirm deletions over", fields["sync_confirm_deletions_over"][:label]
  end
end

# frozen_string_literal: true

require "test_helper"

# Locks in the version-tag scheme the update system relies on:
#   vX.Y.Z-nightly.N  →  vX.Y.Z-rc.N  →  vX.Y.Z  →  vX.(Y+1).0-nightly.1
# The whole channel logic hinges on Gem::Version ordering these correctly
# (it converts `-nightly.1` → `.pre.nightly.1`), so guard it directly.
module RoeUpdater
  class VersionCheckerTest < ActiveSupport::TestCase
    VC = RoeUpdater::VersionChecker

    test "tag_is_prerelease? keys on the suffix, not a specific word" do
      assert_not VC.send(:tag_is_prerelease?, "0.1.0")
      assert_not VC.send(:tag_is_prerelease?, "0.0.39")
      assert VC.send(:tag_is_prerelease?, "0.1.0-nightly.1")
      assert VC.send(:tag_is_prerelease?, "0.1.0-rc.1")
    end

    test "compare_versions orders the prerelease ladder" do
      cmp = ->(a, b) { VC.send(:compare_versions, a, b) }

      # nightly counter is numeric, not lexical (10 beats 2)
      assert_operator cmp.call("0.1.0-nightly.10", "0.1.0-nightly.2"), :>, 0
      # nightly < rc < final
      assert_operator cmp.call("0.1.0-rc.1", "0.1.0-nightly.9"), :>, 0
      assert_operator cmp.call("0.1.0", "0.1.0-rc.1"), :>, 0
      # prior stable < the next cycle's first nightly
      assert_operator cmp.call("0.1.0-nightly.1", "0.0.39"), :>, 0
      assert_operator cmp.call("0.2.0-nightly.1", "0.1.0"), :>, 0
    end

    test "pick_latest picks the highest-precedence [original, stripped] pair" do
      pre = [
        %w[v0.1.0-nightly.1 0.1.0-nightly.1],
        %w[v0.1.0-nightly.10 0.1.0-nightly.10],
        %w[v0.1.0-nightly.2 0.1.0-nightly.2],
        %w[v0.1.0-rc.1 0.1.0-rc.1]
      ]
      assert_equal "0.1.0-rc.1", VC.send(:pick_latest, pre).last

      nightlies = [%w[v0.1.0-nightly.2 0.1.0-nightly.2], %w[v0.1.0-nightly.10 0.1.0-nightly.10]]
      assert_equal "0.1.0-nightly.10", VC.send(:pick_latest, nightlies).last

      stable = [%w[v0.0.39 0.0.39], %w[v0.1.0 0.1.0]]
      assert_equal "0.1.0", VC.send(:pick_latest, stable).last

      assert_nil VC.send(:pick_latest, [])
    end
  end
end

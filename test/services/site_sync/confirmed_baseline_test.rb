# frozen_string_literal: true

require "test_helper"

# A deletion is inferred, never observed: "in the baseline, absent on the peer"
# is a guess that the peer deleted it. So a file the peer has never had must
# not enter the baseline — next sync its absence reads as a deletion, and the
# file is destroyed on the only side that had it.
#
# That rule was implemented at one call site and missing from three others,
# which is how a Roe update — seeding redirects.yml, rewriting docs — produced
# 108 "deletions" nobody had made.
class SiteSync::ConfirmedBaselineTest < ActiveSupport::TestCase
  setup do
    @ledger = SiteSync::Ledger.new
    @recorded = File.exist?(@ledger.send(:ledger_path)) ? File.read(@ledger.send(:ledger_path)) : nil
  end

  teardown do
    path = @ledger.send(:ledger_path)
    @recorded ? File.write(path, @recorded) : FileUtils.rm_f(path)
  end

  def baseline_paths
    JSON.parse(File.read(@ledger.send(:ledger_path)))["files"].keys
  end

  def local_manifest = SiteSync::Ledger.new.current_manifest

  test "a file the peer doesn't have is kept out of the baseline" do
    local = local_manifest
    assert local.any?, "no files to test with"
    peer = local.except(local.keys.first)

    SiteSync::Ledger.write_confirmed!(peer)

    assert_not_includes baseline_paths, local.keys.first,
      "recording it means its absence reads as a deletion next sync"
  end

  test "files both sides have are recorded" do
    local = local_manifest

    SiteSync::Ledger.write_confirmed!(local)

    assert_equal local.keys.sort, baseline_paths.sort
  end

  # Documentation excluded on one side is missing from its manifest entirely.
  # That's a scope difference, not a deletion, and it must not be recorded as
  # agreement — which is what turned 108 doc files into "deleted on live".
  test "a whole directory the peer excludes stays out" do
    local = local_manifest.merge(
      "documentation/roe/guide.md" => { "size" => 1, "mtime" => 1 },
      "documentation/roe/other.md" => { "size" => 1, "mtime" => 1 }
    )
    SiteSync::Ledger.new.write_manifest!(local)
    peer = local.reject { |path, _| path.start_with?("documentation/roe/") }

    SiteSync::Ledger.write_confirmed!(peer)

    assert_empty baseline_paths.select { |p| p.start_with?("documentation/roe/") }
  end

  # Stale drift is visible and recoverable; a wrong baseline is neither.
  test "no peer manifest writes nothing rather than guessing" do
    SiteSync::Ledger.new.write_manifest!("only/this.md" => { "size" => 1, "mtime" => 1 })

    assert_nil SiteSync::Ledger.write_confirmed!(nil)
    assert_nil SiteSync::Ledger.write_confirmed!({})

    assert_equal [ "only/this.md" ], baseline_paths, "the baseline was rewritten anyway"
  end

  # fetch_peer_manifest returns an envelope, not the files map. Passing it by
  # mistake matches no paths and would quietly record an EMPTY baseline — which
  # I did in the first version of this fix, and the tests missed because they
  # called write_confirmed! directly with a bare map.
  test "the manifest envelope is refused, not silently treated as empty" do
    SiteSync::Ledger.new.write_manifest!("kept.md" => { "size" => 1, "mtime" => 1 })
    envelope = { "files" => local_manifest, "fingerprint" => "abc", "file_count" => 1 }

    assert_nil SiteSync::Ledger.write_confirmed!(envelope)
    assert_equal [ "kept.md" ], baseline_paths, "an empty baseline makes every file look newly added"
  end

  # Every call site must hand over the files map, not the envelope.
  test "no caller passes the envelope" do
    offenders = Dir.glob(Rails.root.join("app/**/*.rb")).select do |file|
      File.read(file).match?(/write_confirmed!\(\s*(SiteSync::)?Exchange\.fetch_peer_manifest\s*,/)
    end

    assert_empty offenders.map { |f| f.sub(Rails.root.to_s + "/", "") },
      "fetch_peer_manifest returns an envelope — callers need .dig(\"files\")"
  end

  # The bug was one rule with several implementations, so this guards the shape
  # rather than any single call site.
  test "nothing writes an unconfirmed baseline" do
    offenders = Dir.glob(Rails.root.join("app/**/*.rb")).select do |file|
      next false if file.end_with?("site_sync/ledger.rb")
      File.read(file).match?(/Ledger\.write_current!/)
    end

    assert_empty offenders.map { |f| f.sub(Rails.root.to_s + "/", "") },
      "write_current! records local-only files as if the peer had them"
  end
end

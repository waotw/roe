# frozen_string_literal: true

require "test_helper"
require_relative "../../video_test_helpers"

# The live-video setting keeps video files on this computer that the live
# site never plays: originals once they have web versions (1080p, the
# default) and the 1080p too when 720p is chosen. Site Sync must leave them
# out of everything it compares, quietly remove live's copies on a push, and
# never warn about either. Live, with only web versions, must keep the
# video alive and playable.
class SiteSync::LiveVideoTest < ActiveSupport::TestCase
  include VideoTestHelpers

  LV = SiteSync::LiveVideo
  STATE = { "size" => 1000, "mtime" => 1 }.freeze

  setup do
    setup_video_dir
    # Live has said it can run videos without their originals (the test
    # cache stores nothing, so the answer is stubbed). See "an older live".
    LV.stubs(:peer_ready?).returns(true)
    LV.reset_cache!
  end

  teardown do
    teardown_video_dir
    Medium.where("file_path LIKE ?", "/media/video/zz-lv-%").delete_all
    LV.unstub(:choice) rescue nil
    LV.unstub(:live_side?) rescue nil
    LV.unstub(:peer_ready?) rescue nil
    LV.reset_cache!
  end

  def with_choice(choice)
    LV.stubs(:choice).returns(choice)
    LV.reset_cache!
    yield
  ensure
    LV.unstub(:choice)
    LV.reset_cache!
  end

  def on_live
    LV.stubs(:live_side?).returns(true)
    LV.reset_cache!
    yield
  ensure
    LV.unstub(:live_side?)
    LV.reset_cache!
  end

  def rel(web) = web.delete_prefix("/")

  # ── what's held back ──

  test "1080p (the default) keeps an original with web versions here, and only that" do
    assert_equal "1080p", LV::DEFAULT
    web = fake_variants("zz-lv-a.mp4", renditions: %w[720p 1080p])

    with_choice("1080p") do
      assert LV.held_back?(rel(web))
      assert_includes LV.to_purge, rel(web)
      assert_not LV.held_back?("media/video/variants/zz-lv-a-1080p.mp4"), "the 1080p still goes live"
      assert_not LV.held_back?("media/video/variants/zz-lv-a-720p.mp4")
      assert_not LV.held_back?("media/video/variants/zz-lv-a-video.json"), "live needs the manifest"
    end
  end

  test "720p also keeps the 1080p here" do
    web = fake_variants("zz-lv-b.mp4", renditions: %w[720p 1080p])

    with_choice("720p") do
      assert LV.held_back?(rel(web))
      assert LV.held_back?("media/video/variants/zz-lv-b-1080p.mp4")
      assert_not LV.held_back?("media/video/variants/zz-lv-b-720p.mp4")
      assert_not LV.held_back?("media/video/variants/zz-lv-b-poster.jpg")
    end
  end

  test "original sends everything, as before" do
    web = fake_variants("zz-lv-c.mp4", renditions: %w[720p 1080p])

    with_choice("original") do
      assert_not LV.held_back?(rel(web))
      assert_empty LV.to_purge
    end
  end

  test "a video without web versions sends its original: that's all there is to play" do
    web = fake_variants("zz-lv-d.mp4", renditions: [])

    with_choice("1080p") { assert_not LV.held_back?(rel(web)) }
  end

  test "an original whose web versions are being made waits for them, but isn't purged" do
    web = fake_variants("zz-lv-e.mp4", renditions: [])
    Medium.create!(file_path: web, media_type: "video", variants_status: "processing")

    with_choice("1080p") do
      assert LV.held_back?(rel(web)), "sending it now means uploading it only to remove it next sync"
      assert_not_includes LV.to_purge, rel(web), "live may be playing that very file until the web versions arrive"
    end
  end

  test "a replaced original (stale web versions) isn't held back" do
    web = fake_variants("zz-lv-f.mp4", renditions: %w[720p], size: 1)

    with_choice("1080p") { assert_not LV.held_back?(rel(web)) }
  end

  test "live holds nothing back" do
    web = fake_variants("zz-lv-g.mp4", renditions: %w[720p])

    on_live { assert_not LV.held_back?(rel(web)) }
  end

  # ── an older live site ──

  # Syncing before deploying: an older live would see the original missing,
  # drop the video's record and delete its web versions. So nothing is held
  # back until live has said it can manage without originals.
  test "an older live, one that hasn't said it can manage without originals, gets everything" do
    web = fake_variants("zz-lv-w.mp4", renditions: %w[720p])
    LV.unstub(:peer_ready?)
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(store)
    LV.reset_cache!

    with_choice("1080p") do
      assert_not LV.held_back?(rel(web)), "never heard from live"
      assert_empty LV.to_purge

      LV.record_peer_ready!(nil) # an older live's manifest has no answer
      assert_not LV.held_back?(rel(web))

      LV.record_peer_ready!(true) # this version's live
      assert LV.held_back?(rel(web)), "takes effect as soon as live says so"

      LV.record_peer_ready!(nil) # live rolled back to an older Roe
      assert_not LV.held_back?(rel(web))
    end
  end

  test "this version's live says it can, in its manifest" do
    SiteSync::Ledger.stubs(:current).returns({})
    controller = Api::SiteSync::ExchangeController.new
    rendered = nil
    controller.stubs(:render).with { |json:, **| rendered = json; true }

    controller.manifest

    assert_equal true, rendered[:keeps_videos_without_originals]
  end

  # ── nothing to warn about ──

  test "a held-back original is left out of this computer's manifest" do
    web = fake_variants("zz-lv-h.mp4", renditions: %w[720p])

    with_choice("1080p") do
      manifest = SiteSync::Ledger.current
      assert_not manifest.key?(rel(web))
      assert manifest.key?("media/video/variants/zz-lv-h-720p.mp4")
    end
  end

  test "an original in an older baseline isn't reported as deleted" do
    web = fake_variants("zz-lv-i.mp4", renditions: %w[720p])

    with_choice("1080p") do
      diff = SiteSync::Ledger.diff({}, { rel(web) => STATE })
      assert_empty diff[:deleted], "the drift banner would call the setting a deletion"
    end
  end

  test "switching it on: no push, no pull, no deletion to confirm, no conflict" do
    web = fake_variants("zz-lv-j.mp4", renditions: %w[720p])

    with_choice("1080p") do
      result = SiteSync::Reconciler.reconcile(
        baseline: { rel(web) => STATE }, local: {}, peer: { rel(web) => STATE }
      )

      assert_empty result.push_delete, "asked to confirm deleting a file the setting just kept here"
      assert_empty result.pull, "would download live's copy of a file this computer has"
      assert_empty result.conflicts
    end
  end

  test "live still holding the original isn't a difference" do
    web = fake_variants("zz-lv-k.mp4", renditions: %w[720p])

    with_choice("1080p") do
      files = { rel(web) => STATE, "posts/a.md" => STATE }
      peer = { "files" => files, "fingerprint" => SiteSync::Ledger.fingerprint_of(files) }
      comparable = SiteSync::Ledger.comparable_peer_manifest(peer)

      assert_equal [ "posts/a.md" ], comparable["files"].keys
      assert_equal SiteSync::Ledger.fingerprint_of({ "posts/a.md" => STATE }), comparable["fingerprint"]
    end
  end

  test "the manifest fetched from live drops it" do
    web = fake_variants("zz-lv-l.mp4", renditions: %w[720p])
    files = { rel(web) => STATE, "posts/a.md" => STATE }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, { files: files, fingerprint: "raw", file_count: 2, keeps_videos_without_originals: true }.to_json)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_url).returns("https://live.example")
    SiteSync::Exchange.stubs(:get_from_peer).returns(response)

    with_choice("1080p") do
      peer = SiteSync::Exchange.fetch_peer_manifest
      assert_equal [ "posts/a.md" ], peer["files"].keys
      assert_not_equal "raw", peer["fingerprint"]
    end
  end

  # ── removing live's copies ──

  test "a push asks live to remove its copies, without them being part of the diff" do
    web = fake_variants("zz-lv-m.mp4", renditions: %w[720p])
    post = File.join(RoeSitePaths::SITE_PATH, "posts", "zz-lv-post.md")
    File.write(post, "x")
    sent = nil
    SiteSync::Exchange.stubs(:refresh_peer_ledger!).returns(true)
    SiteSync::Exchange.stubs(:reconcile_peer_content!).returns(true)
    SiteSync::Exchange.stubs(:upload_files).with { |deleted:, **| sent = deleted; true }.returns({ "ok" => true, "deleted" => 1 })

    with_choice("1080p") do
      SiteSync::HttpTransport.push_local_to_live!(diff: { added: [ "posts/zz-lv-post.md" ], modified: [], deleted: [] })
    end

    assert_includes sent, rel(web)
  ensure
    FileUtils.rm_f(post) if post
  end

  # The case from the request: the setting is chosen (or is the default)
  # and nothing else changed. The sync still removes live's copies, quietly:
  # nothing is backed up from live first and nothing is listed as going to
  # live, so there's nothing to confirm or warn about.
  test "a sync with nothing else to send still removes live's copies, and says nothing about it" do
    web = fake_variants("zz-lv-x.mp4", renditions: %w[720p])

    with_choice("1080p") do
      local = SiteSync::Ledger.current
      # Live and the last sync agree with this computer on everything,
      # except that live still has the original.
      peer_files = local.merge(rel(web) => STATE)
      SiteSync::Ledger.stubs(:recorded).returns({ "files" => peer_files })
      SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(
        SiteSync::Ledger.comparable_peer_manifest({ "files" => peer_files, "fingerprint" => "x" })
      )
      transport = mock("transport")
      transport.expects(:backup_live_to_local!).never
      transport.expects(:push_local_to_live!).with { |diff:, tidy:, **| diff.values.all?(&:empty?) && tidy }
      SiteSync.stubs(:transport).returns(transport)

      job = SiteSyncTransferJob.new
      job.instance_variable_set(:@to_live, { modified: [], added: [], deleted: [] })
      job.stubs(:update_step)
      job.send(:perform_sync)

      assert job.instance_variable_get(:@pushed), "live's content is reconciled after"
      assert_empty job.instance_variable_get(:@to_live).values.flatten, "nothing listed as going to live"
    end
  end

  test "nothing to tidy, nothing pushed" do
    with_choice("1080p") do
      SiteSync::Ledger.stubs(:recorded).returns({ "files" => {} })
      SiteSync::Ledger.stubs(:current).returns({})
      SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => {}, "kept_here_on_peer" => [] })
      transport = mock("transport")
      transport.expects(:push_local_to_live!).never
      SiteSync.stubs(:transport).returns(transport)

      job = SiteSyncTransferJob.new
      job.stubs(:update_step)
      job.send(:perform_sync)
    end
  end

  test "this computer refuses to delete its own copy, whatever a peer sends" do
    web = fake_variants("zz-lv-n.mp4", renditions: %w[720p])

    with_choice("1080p") do
      removed = SiteSync::SiteWriter.delete_paths(root: RoeSitePaths::SITE_PATH, paths: [ rel(web) ])
      assert_empty removed
      assert File.file?(File.join(RoeSitePaths::SITE_PATH, rel(web)))
    end
  end

  test "rsync rules name each held-back file, quoted, anchored at /site" do
    fake_variants("zz-lv-o two [x].mp4", renditions: %w[720p])

    with_choice("1080p") do
      rule = LV.rsync_exclude_args.find { |a| a.include?("zz-lv-o") }
      assert rule, "the original is excluded"
      assert_equal [ "--exclude=/media/video/zz-lv-o two \\[x\\].mp4" ], Shellwords.split(rule),
        "one shell word, with rsync's wildcard brackets made literal"
    end
  end

  # ── live, with only the web versions ──

  def without_original(web)
    FileUtils.rm_f(File.join(RoeSitePaths::SITE_PATH, rel(web)))
  end

  test "on live the player plays the web versions of a video whose original is elsewhere" do
    web = fake_variants("zz-lv-p.mp4", renditions: %w[720p 1080p])
    without_original(web)

    on_live do
      plan = VideoRenderer.new(web).plan
      assert_equal %w[/media/video/variants/zz-lv-p-720p.mp4 /media/video/variants/zz-lv-p-1080p.mp4], plan.sources.map { _1[:src] }
      assert_equal "/media/video/variants/zz-lv-p-poster.jpg", plan.poster
    end
  end

  test "with 720p chosen, live plays the 720p and skips the 1080p it doesn't have" do
    web = fake_variants("zz-lv-q.mp4", renditions: %w[720p 1080p])
    without_original(web)
    FileUtils.rm_f(VideoVariantGenerator.variant_path_for(File.join(RoeSitePaths::SITE_PATH, rel(web)), "1080p"))

    on_live do
      assert_equal %w[/media/video/variants/zz-lv-q-720p.mp4], VideoRenderer.new(web).plan.sources.map { _1[:src] }
    end
  end

  test "on live the video's record and web versions stay, and a new one gets a record" do
    kept = fake_variants("zz-lv-r.mp4", renditions: %w[720p])
    arriving = fake_variants("zz-lv-s.mp4", renditions: %w[720p])
    Medium.create!(file_path: kept, media_type: "video")
    without_original(kept)
    without_original(arriving)

    on_live do
      ContentSync.new.sync_media
      VideoVariantGenerator.prune_orphans!
    end

    assert Medium.exists?(file_path: kept), "removing the record deletes its web versions"
    assert Medium.exists?(file_path: arriving, media_type: "video"), "a video that arrived without its original"
    assert File.file?(File.join(RoeSitePaths::SITE_PATH, "media/video/variants/zz-lv-r-720p.mp4"))
  end

  test "on live a post naming the original isn't missing media" do
    web = fake_variants("zz-lv-t.mp4", renditions: %w[720p])
    without_original(web)
    Current.media_file_set = nil

    on_live { assert_includes Post.media_file_set, web }
  ensure
    Current.media_file_set = nil
  end

  test "on this computer a missing original still means deleted: its web versions go" do
    web = fake_variants("zz-lv-u.mp4", renditions: %w[720p])
    without_original(web)

    VideoVariantGenerator.prune_orphans!

    assert_not File.file?(File.join(RoeSitePaths::SITE_PATH, "media/video/variants/zz-lv-u-720p.mp4"))
    assert_empty VideoVariantGenerator.stand_in_originals
  end

  test "a manifest can only vouch for an original in its own folder" do
    web = fake_variants("zz-lv-v.mp4", renditions: %w[720p])
    without_original(web)
    manifest_path = VideoVariantGenerator.manifest_path(File.join(RoeSitePaths::SITE_PATH, rel(web)))
    data = JSON.parse(File.read(manifest_path))
    data["source"]["path"] = "/media/video/elsewhere/zz-lv-other.mp4"
    File.write(manifest_path, data.to_json)

    on_live { assert_not_includes VideoVariantGenerator.stand_in_originals, "/media/video/elsewhere/zz-lv-other.mp4" }
  end

  # The whole trip on live: the push's delete list arrives, live removes the
  # original, live's content sync runs (as it does after every push), and
  # the video is still a video — record, web versions, playable page.
  test "on live, removing the original keeps the video whole" do
    web = fake_variants("zz-lv-y.mp4", renditions: %w[720p 1080p])
    Medium.create!(file_path: web, media_type: "video")
    purge = with_choice("1080p") { LV.to_purge }
    assert_includes purge, rel(web)

    on_live do
      removed = SiteSync::SiteWriter.delete_paths(root: RoeSitePaths::SITE_PATH, paths: purge)
      assert_includes removed, rel(web), "live accepts the removal"

      ContentSync.new.sync_media
      VideoVariantGenerator.prune_orphans!

      assert Medium.exists?(file_path: web)
      assert_equal 2, VideoRenderer.new(web).plan.sources.size
      assert File.file?(File.join(RoeSitePaths::SITE_PATH, "media/video/variants/zz-lv-y-720p.mp4"))
    end
  end

  # The editor's checks on live ("File not found under site/media." under a
  # video field; filling in a post's duration) ask for the original.
  test "on live the editor finds a video whose original is elsewhere, by its web version" do
    web = fake_variants("zz-lv-z.mp4", renditions: %w[720p 1080p])
    without_original(web)

    on_live do
      assert_equal File.join(RoeSitePaths::SITE_PATH, "media/video/variants/zz-lv-z-720p.mp4"),
        VideoVariantGenerator.stand_in_file_for(web), "the smallest: same length, quickest to read"
      assert_nil VideoVariantGenerator.stand_in_file_for("/media/video/zz-lv-nothing.mp4")
      assert_nil VideoVariantGenerator.stand_in_file_for("/media/video/variants/zz-lv-z-720p.mp4")
      assert_nil VideoVariantGenerator.stand_in_file_for("/media/../zz-lv-z.mp4")
    end
    assert_nil VideoVariantGenerator.stand_in_file_for(web), "on this computer a missing original is a deleted one"
  end

  # The media library's "File size" sort on live: what the video takes up
  # there, not 0 bytes for the original it doesn't have.
  test "on live a video without its original is sized by the files live holds for it" do
    web = fake_variants("zz-lv-sz.mp4", renditions: %w[720p 1080p])
    without_original(web)
    source = File.join(RoeSitePaths::SITE_PATH, rel(web))
    expected = VideoVariantGenerator.all_variant_paths(source).sum { |p| File.size?(p) || 0 }
    assert expected.positive?

    on_live { assert_equal expected, VideoVariantGenerator.stand_in_size_for(web) }
    assert_nil VideoVariantGenerator.stand_in_size_for(web), "on this computer, unchanged"

    medium = Medium.create!(file_path: web, media_type: "video")
    html = on_live { ApplicationController.render(partial: "admin/medium/media_card", locals: { media: medium, usages: [] }) }
    assert_includes html, %(data-file-size="#{expected}"), "the card the sort reads"
  end
end

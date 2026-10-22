# frozen_string_literal: true

require "test_helper"
require_relative "../video_test_helpers"

# A video whose web versions stopped part-way — the jobs program ended mid-
# encode, so Solid Queue marked that job failed — stayed "optimizing" for
# good: the failed job still counted as work under way, and nothing queued
# the missing versions again. These check that it's noticed and finished.
class VideoResumeTest < ActiveSupport::TestCase
  include VideoTestHelpers
  include ActiveJob::TestHelper

  VVG = VideoVariantGenerator

  setup do
    setup_video_dir
    # The test cache stores nothing; the retry count needs one that does.
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    VVG.stubs(:available?).returns(true)
    VVG.stubs(:solid_queue?).returns(true)
  end

  teardown do
    teardown_video_dir
    Medium.where("file_path LIKE ?", "/media/video/zz-resume-%").delete_all
    SolidQueue::Job.where(class_name: "TranscodeVideoJob").destroy_all
  end

  # The 720p and poster made, the 1080p not: what a video looks like after
  # the encode was ended during its last version.
  def stopped_partway(name, status: "processing")
    web = fake_variants(name, renditions: %w[720p])
    path = VVG.manifest_path(File.join(RoeSitePaths::SITE_PATH, web.delete_prefix("/")))
    File.write(path, JSON.parse(File.read(path)).merge("complete" => false, "wanted" => %w[720p 1080p]).to_json)
    # Created first, then given its status: creating a video record queues
    # its web versions, which sets the status itself.
    Medium.create!(file_path: web, media_type: "video")
    Medium.where(file_path: web).update_all(variants_status: status)
    clear_enqueued_jobs
    @cache.delete(VVG.queue_cache_key(web))
    web
  end

  def queue_job(web, name)
    SolidQueue::Job.create!(queue_name: "video", class_name: "TranscodeVideoJob",
                            arguments: { "arguments" => [ web, name, false ] })
  end

  test "a failed job isn't work under way; a waiting one is" do
    VVG.unstub(:solid_queue?)
    ActiveJob::Base.stubs(:queue_adapter).returns(ActiveJob::QueueAdapters::SolidQueueAdapter.new)
    web = "/media/video/zz-resume-a.mp4"

    job = queue_job(web, "1080p")
    assert_includes VVG.videos_with_jobs, web

    SolidQueue::FailedExecution.create!(job: job, exception: RuntimeError.new("SolidQueue::Processes::ProcessPrunedError"))
    assert_not_includes VVG.videos_with_jobs, web, "it never runs again"
  end

  test "a video that stopped part-way is found; one being worked on, finished or failed isn't" do
    stopped = stopped_partway("zz-resume-b.mp4")
    working = stopped_partway("zz-resume-c.mp4")
    failed = stopped_partway("zz-resume-d.mp4", status: "failed")
    done = fake_variants("zz-resume-e.mp4", renditions: %w[720p])
    Medium.create!(file_path: done, media_type: "video")
    Medium.where(file_path: done).update_all(variants_status: "processing")
    VVG.stubs(:videos_with_jobs).returns(Set[working])

    found = VVG.interrupted.map(&:file_path)

    assert_includes found, stopped
    assert_not_includes found, working
    assert_not_includes found, failed, "a real error is shown, not retried by itself"
    assert_not_includes found, done
  end

  test "it's queued again, and Optimize Videos offers it meanwhile" do
    web = stopped_partway("zz-resume-f.mp4")
    VVG.stubs(:videos_with_jobs).returns(Set.new)
    @cache.write(VVG.queue_cache_key(web), true) # left over from the run that stopped

    assert_includes VVG.needing_optimization.map(&:file_path), web,
      "the old queue marker kept it looking busy for hours"

    assert_enqueued_with(job: TranscodeVideoJob, args: [ web, "1080p", false ]) do
      assert_equal 1, VVG.resume_interrupted!
    end
    assert_equal "queued", Medium.find_by(file_path: web).variants_status
  end

  test "after two tries it's marked failed, with a reason, not retried forever" do
    web = stopped_partway("zz-resume-g.mp4")
    VVG.stubs(:videos_with_jobs).returns(Set.new)

    2.times do
      assert_equal 1, VVG.resume_interrupted!
      Medium.where(file_path: web).update_all(variants_status: "processing") # stopped again
    end

    assert_no_enqueued_jobs(only: TranscodeVideoJob) { assert_equal 0, VVG.resume_interrupted! }
    assert_equal "failed", Medium.find_by(file_path: web).variants_status
    assert_match "stopped part-way 2 times", VVG.last_error(web)
  end

  test "nothing happens where videos aren't made" do
    stopped_partway("zz-resume-h.mp4")
    VVG.stubs(:videos_with_jobs).returns(Set.new)
    VVG.stubs(:available?).returns(false)

    assert_no_enqueued_jobs { assert_equal 0, VVG.resume_interrupted! }
  end

  test "the jobs program checks as it starts, and nowhere on live" do
    hooks = SolidQueue::Supervisor.lifecycle_hooks[:start]
    assert hooks.any?, "registered by config/initializers/video_variants.rb"

    VVG.expects(:resume_interrupted!).returns(0)
    hooks.each(&:call)

    assert_nil YAML.load_file(Rails.root.join("config/recurring.yml")).dig("development", "resume_video_variants"),
      "no timer: it runs at start, and Optimize Videos covers the rest"
  end

  # ── jobs of a jobs program that's gone ──

  def dead_pid
    pid = ::Process.spawn("true")
    ::Process.wait(pid)
    pid
  end

  def job_process(pid:, host: Socket.gethostname)
    SolidQueue::Process.create!(kind: "Worker", pid: pid, hostname: host, name: "worker-#{SecureRandom.hex(4)}",
                                last_heartbeat_at: Time.current)
  end

  def claim(job, process)
    job.ready_execution&.destroy!
    SolidQueue::ClaimedExecution.create!(job: job, process: process)
  end

  test "a job still claimed by a process that's gone isn't work under way" do
    VVG.unstub(:solid_queue?)
    ActiveJob::Base.stubs(:queue_adapter).returns(ActiveJob::QueueAdapters::SolidQueueAdapter.new)
    alive = "/media/video/zz-resume-alive.mp4"
    gone = "/media/video/zz-resume-gone.mp4"
    claim(queue_job(alive, "1080p"), job_process(pid: ::Process.pid))
    claim(queue_job(gone, "1080p"), job_process(pid: dead_pid))

    busy = VVG.videos_with_jobs

    assert_includes busy, alive
    assert_not_includes busy, gone
  ensure
    SolidQueue::Process.delete_all
  end

  test "a gone process's jobs are handed back now, not in five minutes; others are left alone" do
    gone_proc = job_process(pid: dead_pid)
    running_proc = job_process(pid: ::Process.pid)
    elsewhere = job_process(pid: dead_pid, host: "another-computer")
    gone_job = queue_job("/media/video/zz-resume-x.mp4", "1080p")
    claim(gone_job, gone_proc)

    assert_equal 1, VVG.release_jobs_of_gone_processes!

    assert gone_job.reload.failed_execution, "Solid Queue's own clean-up: failed, and the lock passed on"
    assert_not SolidQueue::Process.exists?(gone_proc.id)
    assert SolidQueue::Process.exists?(running_proc.id), "a running one is never touched"
    assert SolidQueue::Process.exists?(elsewhere.id), "another computer's can't be checked from here"
  ensure
    SolidQueue::Process.delete_all
  end

  test "Optimize Videos and the start check both hand back a gone process's jobs first" do
    VVG.expects(:release_jobs_of_gone_processes!).twice.returns(0)
    VVG.expects(:release_stuck_transcodes!).twice.returns(0)
    VVG.stubs(:needing_optimization).returns([])
    VVG.stubs(:interrupted).returns([])

    VVG.optimize_all!
    VVG.resume_interrupted!
  end

  # ── waiting for a lock nobody holds ──
  #
  # What roe_site was left with: the 720p finished, the jobs program was
  # stopped as Solid Queue handed the lock to the 1080p, and only the
  # lock's return was saved. The 1080p stayed waiting for its own expiry,
  # hours away, with the lock free and nothing encoding.

  LOCK = "TranscodeVideoJob/video-transcode"

  # Enqueued the real way, so Solid Queue does its own lock bookkeeping:
  # the first takes the lock and is ready, the next waits behind it.
  def enqueue_transcode(web, name)
    SolidQueue::Job.enqueue(TranscodeVideoJob.new(web, name, false))
    SolidQueue::Job.where(class_name: "TranscodeVideoJob").order(:id).last
  end

  # The 720p done, its finish recorded — but of the hand-off that should
  # come with it, only `lock_returned` (or nothing) was saved.
  def finish_without_handing_on(job, lock_returned:)
    job.ready_execution&.destroy!
    job.update!(finished_at: Time.current)
    SolidQueue::Semaphore.where(key: LOCK).update_all(value: 1) if lock_returned
  end

  def with_solid_queue
    VVG.unstub(:solid_queue?)
    ActiveJob::Base.stubs(:queue_adapter).returns(ActiveJob::QueueAdapters::SolidQueueAdapter.new)
    SolidQueue::Semaphore.delete_all
    SolidQueue::BlockedExecution.delete_all
    yield
  ensure
    SolidQueue::Process.delete_all
    SolidQueue::Semaphore.delete_all
    SolidQueue::BlockedExecution.delete_all
  end

  test "a transcode waiting for a free lock with nothing encoding is released, and runs" do
    with_solid_queue do
      first = enqueue_transcode("/media/video/zz-resume-s.mp4", "720p")
      job = enqueue_transcode("/media/video/zz-resume-s.mp4", "1080p")
      assert job.blocked_execution, "Solid Queue made it wait behind the 720p"
      finish_without_handing_on(first, lock_returned: true)

      assert VVG.stuck_transcodes?
      assert_not_includes VVG.videos_with_jobs, "/media/video/zz-resume-s.mp4", "stuck isn't under way"

      assert_equal 1, VVG.release_stuck_transcodes!
      job.reload
      assert job.ready_execution, "ready to run"
      assert_nil job.blocked_execution
      assert_equal 0, SolidQueue::Semaphore.find_by(key: LOCK).value, "and it holds the lock, as usual"
      assert_not VVG.stuck_transcodes?
    end
  end

  test "the same when the lock was never given back but nothing holds it" do
    with_solid_queue do
      first = enqueue_transcode("/media/video/zz-resume-t.mp4", "720p")
      job = enqueue_transcode("/media/video/zz-resume-t.mp4", "1080p")
      finish_without_handing_on(first, lock_returned: false)

      assert_equal 1, VVG.release_stuck_transcodes!
      assert job.reload.ready_execution
    end
  end

  test "a transcode waiting behind one that's encoding is just waiting" do
    with_solid_queue do
      running = enqueue_transcode("/media/video/zz-resume-u.mp4", "720p")
      waiting = enqueue_transcode("/media/video/zz-resume-u.mp4", "1080p")
      claim(running, job_process(pid: ::Process.pid))

      assert_not VVG.stuck_transcodes?
      assert_equal 0, VVG.release_stuck_transcodes!
      assert waiting.reload.blocked_execution, "left in line"
      assert_includes VVG.videos_with_jobs, "/media/video/zz-resume-u.mp4"
    end
  end

  test "a transcode waiting behind one that's ready to run is just waiting" do
    with_solid_queue do
      enqueue_transcode("/media/video/zz-resume-v.mp4", "720p") # ready: it has the lock
      waiting = enqueue_transcode("/media/video/zz-resume-v.mp4", "1080p")

      assert_not VVG.stuck_transcodes?
      assert_equal 0, VVG.release_stuck_transcodes!
      assert waiting.reload.blocked_execution
    end
  end

  # What a restart mid-720p left on this computer: Solid Queue gave the
  # running 720p five seconds, put it back in the queue, and as the encode
  # ended the lock was given back but the 1080p's move to ready rolled
  # back. The 720p, ready again, ran without the lock — so a check that
  # took "a transcode is ready" to mean "the lock is held" saw nothing
  # wrong, and the 1080p waited for hours.
  test "a free lock with a transcode waiting is stuck, even with another ready to run" do
    with_solid_queue do
      enqueue_transcode("/media/video/zz-resume-w.mp4", "720p")
      waiting = enqueue_transcode("/media/video/zz-resume-w.mp4", "1080p")
      SolidQueue::Semaphore.where(key: LOCK).update_all(value: 1) # given back; hand-off lost

      assert VVG.stuck_transcodes?
      assert_equal 1, VVG.release_stuck_transcodes!
      assert waiting.reload.ready_execution
      assert_equal 0, SolidQueue::Semaphore.find_by(key: LOCK).value
    end
  end
end

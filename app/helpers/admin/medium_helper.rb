module Admin::MediumHelper
  def variant_generation_status
    return { available: false } unless ImageVariantGenerator.available?

    # Count pending variant generation jobs
    pending_jobs = SolidQueue::Job
      .where(class_name: "GenerateImageVariantsJob")
      .where(finished_at: nil)
      .count

    # Check if worker is alive
    worker_alive = SolidQueue::Process
      .where("last_heartbeat_at > ?", 30.seconds.ago)
      .exists?

    # Only consider worker "dead" if it's been dead AND jobs are old
    oldest_pending_job = SolidQueue::Job
      .where(class_name: "GenerateImageVariantsJob")
      .where(finished_at: nil)
      .order(:created_at)
      .first

    worker_actually_dead = !worker_alive && oldest_pending_job && oldest_pending_job.created_at < 1.minute.ago


    # Count claimed (in-progress) jobs
    claimed_jobs = SolidQueue::ClaimedExecution
      .joins("INNER JOIN solid_queue_jobs ON solid_queue_jobs.id = solid_queue_claimed_executions.job_id")
      .where("solid_queue_jobs.class_name = ?", "GenerateImageVariantsJob")
      .count

    # Count failed jobs (development only)
    failed_jobs = []
    if Rails.env.development?
      # Only show ACTUALLY failed jobs (not ones that succeeded after retry)
      failed_executions = SolidQueue::FailedExecution
        .joins("INNER JOIN solid_queue_jobs ON solid_queue_jobs.id = solid_queue_failed_executions.job_id")
        .where("solid_queue_jobs.class_name = ?", "GenerateImageVariantsJob")
        .where("solid_queue_jobs.finished_at IS NULL")  # Add this - only show jobs that never finished
        .limit(5)

      failed_jobs = failed_executions.map do |fe|
        error_data = fe.error || {}
        {
          job_id: fe.job_id,
          error_class: error_data["exception_class"],
          error_message: error_data["message"],
          backtrace: error_data["backtrace"]&.first(3)
        }
      end
    end

    # Count ALL images and their variant status
    total_images = Medium.where("file_path LIKE ?", "%/media/images/%").count
    images_with_variants = 0
    images_without_variants = 0

    Medium.where("file_path LIKE ?", "%/media/images/%").find_each do |medium|
      path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, ""))
      next unless File.exist?(path)

      if ImageVariantGenerator.variants_exist?(path)
        images_with_variants += 1
      else
        images_without_variants += 1
      end
    end

    {
      available: true,
      pending_jobs: pending_jobs,
      claimed_jobs: claimed_jobs,
      failed_jobs: failed_jobs,
      worker_alive: worker_alive,
      total_images: total_images,
      with_variants: images_with_variants,
      without_variants: images_without_variants,
      active: pending_jobs > 0 || claimed_jobs > 0,
      all_optimized: images_without_variants == 0 && total_images > 0
    }
  end
end

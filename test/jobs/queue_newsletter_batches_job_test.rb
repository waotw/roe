require "test_helper"

class QueueNewsletterBatchesJobTest < ActiveJob::TestCase
  def setup
    @post = create(:post, metadata: { "title" => "Test Newsletter", "status" => "published", "audience" => "public", "date" => "2024-01-01" })
    @job = QueueNewsletterBatchesJob.new
  end

  test "queues batches for all eligible recipients" do
    # Create 5 subscribed members
    members = create_list(:member, 5, newsletter_status: :subscribed, status: :active)

    assert_enqueued_jobs 1, only: SendNewsletterJob do
      QueueNewsletterBatchesJob.perform_now(@post.id)
    end

    job = enqueued_jobs.last
    assert_equal @post.id, job[:args][0]
    assert_equal 5, job[:args][1].size
    assert_equal members.map(&:id).sort, job[:args][1].sort
  end

  test "respects BATCH_SIZE constant" do
    # Create 600 members to trigger 2 batches
    create_list(:member, 600, newsletter_status: :subscribed, status: :active)

    assert_enqueued_jobs 2, only: SendNewsletterJob do
      QueueNewsletterBatchesJob.perform_now(@post.id)
    end
  end

  test "filters paid posts to paid members only" do
    paid_post = create(:post, metadata: { "title" => "Paid Newsletter", "status" => "published", "audience" => "paid", "date" => "2024-01-01" })
    
    paid_members = create_list(:member, 3, :paid, newsletter_status: :subscribed, status: :active)
    free_members = create_list(:member, 3, newsletter_status: :subscribed, status: :active)

    QueueNewsletterBatchesJob.perform_now(paid_post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    # Should only include paid members
    assert_equal 3, recipient_ids.size
    paid_members.each do |member|
      assert_includes recipient_ids, member.id
    end
    free_members.each do |member|
      assert_not_includes recipient_ids, member.id
    end
  end

  test "excludes unsubscribed members" do
    subscribed = create(:member, newsletter_status: :subscribed, status: :active)
    unsubscribed = create(:member, newsletter_status: :unsubscribed, status: :active)

    QueueNewsletterBatchesJob.perform_now(@post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_includes recipient_ids, subscribed.id
    assert_not_includes recipient_ids, unsubscribed.id
  end

  test "excludes inactive members" do
    active = create(:member, newsletter_status: :subscribed, status: :active)
    cancelled = create(:member, :cancelled, newsletter_status: :subscribed)

    QueueNewsletterBatchesJob.perform_now(@post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_includes recipient_ids, active.id
    assert_not_includes recipient_ids, cancelled.id
  end

  test "excludes members who already received this post" do
    member_received = create(:member, newsletter_status: :subscribed, status: :active)
    member_new = create(:member, newsletter_status: :subscribed, status: :active)

    # Record that member_received already got this newsletter
    NewsletterSend.create!(
      post: @post,
      member: member_received,
      sent_at: Time.current
    )

    QueueNewsletterBatchesJob.perform_now(@post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_not_includes recipient_ids, member_received.id
    assert_includes recipient_ids, member_new.id
  end

  test "excludes Substack-imported members for Substack posts" do
    import = create(:import, source_type: 'substack', status: 'completed')
    
    # Mark post as Substack-imported
    @post.update!(metadata: @post.metadata.merge('substack_post_id' => '12345'))
    
    regular_member = create(:member, newsletter_status: :subscribed, status: :active)
    substack_member = create(:member, newsletter_status: :subscribed, status: :active, import: import)

    QueueNewsletterBatchesJob.perform_now(@post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_includes recipient_ids, regular_member.id
    assert_not_includes recipient_ids, substack_member.id
  end

  test "allows specific member_ids to bypass filters" do
    subscribed = create(:member, newsletter_status: :subscribed, status: :active)
    unsubscribed = create(:member, newsletter_status: :unsubscribed, status: :active)
    specific_ids = [ subscribed.id, unsubscribed.id ]

    QueueNewsletterBatchesJob.perform_now(@post.id, specific_ids)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    # Should include both even though one is unsubscribed
    assert_equal 2, recipient_ids.size
    assert_includes recipient_ids, subscribed.id
    assert_includes recipient_ids, unsubscribed.id
  end

  test "handles empty recipient list gracefully" do
    # No members created
    assert_enqueued_jobs 0, only: SendNewsletterJob do
      QueueNewsletterBatchesJob.perform_now(@post.id)
    end
  end

  test "raises error for non-existent post" do
    assert_raises(ActiveRecord::RecordNotFound) do
      QueueNewsletterBatchesJob.perform_now(99999)
    end
  end

  test "divides recipients into correct batch sizes" do
    # Create 550 members - should result in 2 batches (500 + 50)
    members = create_list(:member, 550, newsletter_status: :subscribed, status: :active)

    QueueNewsletterBatchesJob.perform_now(@post.id)

    assert_equal 2, enqueued_jobs.size
    
    # First batch should have 500
    first_batch = enqueued_jobs.first[:args][1]
    assert_equal 500, first_batch.size
    
    # Second batch should have 50
    second_batch = enqueued_jobs.last[:args][1]
    assert_equal 50, second_batch.size
  end

  test "public posts go to all subscribed members regardless of tier" do
    public_post = create(:post, metadata: { "title" => "Public Post", "status" => "published", "audience" => "public", "date" => "2024-01-01" })
    
    free_member = create(:member, tier: :free, newsletter_status: :subscribed, status: :active)
    paid_member = create(:member, :paid, newsletter_status: :subscribed, status: :active)

    QueueNewsletterBatchesJob.perform_now(public_post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_includes recipient_ids, free_member.id
    assert_includes recipient_ids, paid_member.id
  end

  test "does not double-queue same members" do
    member = create(:member, newsletter_status: :subscribed, status: :active)
    
    # First send
    QueueNewsletterBatchesJob.perform_now(@post.id)
    assert_equal 1, enqueued_jobs.size
    
    # Record the send
    NewsletterSend.create!(
      post: @post,
      member: member,
      sent_at: Time.current
    )
    
    # Clear jobs
    enqueued_jobs.clear
    
    # Second attempt - should have no recipients
    QueueNewsletterBatchesJob.perform_now(@post.id)
    assert_equal 0, enqueued_jobs.size
  end

  test "includes import_id in recipient selection logic" do
    import = create(:import, source_type: 'substack', status: 'completed')
    
    @post.update!(metadata: @post.metadata.merge('substack_post_id' => '12345'))
    
    # Member without import_id
    regular_member = create(:member, newsletter_status: :subscribed, status: :active, import: nil)
    # Member with substack import
    substack_member = create(:member, newsletter_status: :subscribed, status: :active, import: import)

    QueueNewsletterBatchesJob.perform_now(@post.id)

    job = enqueued_jobs.last
    recipient_ids = job[:args][1]
    
    assert_includes recipient_ids, regular_member.id
    assert_not_includes recipient_ids, substack_member.id
  end

  test "logs batch information" do
    create_list(:member, 10, newsletter_status: :subscribed, status: :active)

    Rails.logger.expects(:info).with(regexp_matches(/Queueing \d+ batch jobs for \d+ recipients/))
    
    QueueNewsletterBatchesJob.perform_now(@post.id)
  end
end

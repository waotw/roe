require "test_helper"

class SendNewsletterJobTest < ActiveJob::TestCase
  def setup
    @post = create(:post, metadata: { "title" => "Test Newsletter", "status" => "published", "audience" => "public", "date" => "2024-01-01" })
    @member = create(:member, email: 'test@example.com', name: 'Test User')
    @job = SendNewsletterJob.new

    # Ensure SiteConfig is set up
    SiteConfig.find_by(file_path: 'site/system/global/site.yml')&.update!(
      config: { 'author_email' => 'author@example.com', 'author' => 'Test Author' }
    )

    # Configure Postmark
    PostmarkConfig.current.update!(server_token: 'test-token')
  end

  test "sends newsletter to members" do
    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-123' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal 1, result[:sent]
    assert_equal 0, result[:failed]
  end

  test "skips members who already received" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    # Should not call PostmarkService
    PostmarkService.expects(:send_newsletter_batch).never

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal 0, result[:sent]
    assert_equal 0, result[:failed]
  end

  test "creates NewsletterSend record on success" do
    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-abc123' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    assert_difference 'NewsletterSend.count', 1 do
      SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    end

    ns = NewsletterSend.last
    assert_equal @post, ns.post
    assert_equal @member, ns.member
    assert_equal 'msg-abc123', ns.message_id
    assert ns.sent_at.present?
  end

  test "handles batch with multiple members" do
    member2 = create(:member, email: 'test2@example.com', name: 'Test User 2')

    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-1' },
        { 'ErrorCode' => 0, 'MessageID' => 'msg-2' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id, member2.id ])
    
    assert_equal 2, result[:sent]
    assert_equal 0, result[:failed]
  end

  test "handles partial failures in batch" do
    member2 = create(:member, email: 'test2@example.com', name: 'Test User 2')

    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-1' },
        { 'ErrorCode' => 406, 'Message' => 'Invalid recipient' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id, member2.id ])
    
    assert_equal 1, result[:sent]
    assert_equal 1, result[:failed]
  end

  test "handles complete batch failure" do
    mock_result = {
      success: false,
      error: 'API Error'
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal 0, result[:sent]
    assert_equal 1, result[:failed]
  end

  test "uses NewsletterRenderer for content" do
    mock_renderer = mock('renderer')
    mock_renderer.expects(:render).returns('<html>Test content</html>')
    NewsletterRenderer.expects(:new).with(@post, @member).returns(mock_renderer)

    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-123' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    SendNewsletterJob.perform_now(@post.id, [ @member.id ])
  end

  test "builds correct message structure" do
    member = create(:member, email: 'recipient@example.com', name: 'John Doe')

    PostmarkService.expects(:send_newsletter_batch).with do |args|
      messages = args[:messages]
      message = messages.first
      
      message[:From] == 'Test Author <author@example.com>' &&
      message[:To] == 'John Doe <recipient@example.com>' &&
      message[:Subject] == 'Test Newsletter' &&
      message[:HtmlBody].present? &&
      message[:TextBody].present? &&
      message[:MessageStream] == 'broadcast' &&
      message[:Tag] == 'newsletter' &&
      message[:Metadata][:post_id] == @post.id.to_s &&
      message[:Metadata][:member_id] == member.id.to_s
    end.returns({ success: true, results: [{ 'ErrorCode' => 0, 'MessageID' => 'msg-1' }] })

    SendNewsletterJob.perform_now(@post.id, [ member.id ])
  end

  test "retries on rate limit (429)" do
    fail_result = { success: false, error: 'Rate limited (429)' }
    success_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-123' }
      ]
    }

    PostmarkService.expects(:send_newsletter_batch).twice.returns(fail_result, success_result)

    # Job should sleep between retries
    @job.expects(:sleep).with(2) # 2^1 seconds

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal 1, result[:sent]
  end

  test "gives up after max retries" do
    fail_result = { success: false, error: 'Rate limited (429)' }

    PostmarkService.expects(:send_newsletter_batch).times(3).returns(fail_result)

    # Should sleep for 2s and 4s (2^1 and 2^2)
    @job.expects(:sleep).with(2)
    @job.expects(:sleep).with(4)

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal 0, result[:sent]
    assert_equal 1, result[:failed]
  end

  test "processes members in bulk batches of 100" do
    members = create_list(:member, 150, newsletter_status: :subscribed)
    member_ids = members.map(&:id)

    # Should make 2 API calls (100 + 50)
    PostmarkService.expects(:send_newsletter_batch).twice.returns(
      { success: true, results: Array.new(100) { { 'ErrorCode' => 0, 'MessageID' => 'msg-1' } } },
      { success: true, results: Array.new(50) { { 'ErrorCode' => 0, 'MessageID' => 'msg-1' } } }
    )

    result = SendNewsletterJob.perform_now(@post.id, member_ids)
    
    assert_equal 150, result[:sent]
  end

  test "sleeps between bulk batches" do
    members = create_list(:member, 150, newsletter_status: :subscribed)
    member_ids = members.map(&:id)

    PostmarkService.expects(:send_newsletter_batch).twice.returns(
      { success: true, results: Array.new(100) { { 'ErrorCode' => 0, 'MessageID' => 'msg-1' } } },
      { success: true, results: Array.new(50) { { 'ErrorCode' => 0, 'MessageID' => 'msg-1' } } }
    )

    @job.expects(:sleep).with(0.2)

    SendNewsletterJob.perform_now(@post.id, member_ids)
  end

  test "finds or creates NewsletterSend to avoid duplicates" do
    # Pre-create a send record
    existing = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: 1.hour.ago,
      message_id: 'old-msg'
    )

    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'new-msg' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    # Should not create duplicate, should use existing
    assert_no_difference 'NewsletterSend.count' do
      SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    end

    # Record should be updated
    existing.reload
    assert_equal 'new-msg', existing.message_id
  end

  test "handles missing members gracefully" do
    non_existent_id = 99999
    existing_member = create(:member)

    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-1' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    # Should only send to existing member
    result = SendNewsletterJob.perform_now(@post.id, [ non_existent_id, existing_member.id ])
    
    assert_equal 1, result[:sent]
  end

  test "uses default from when SiteConfig not set" do
    SiteConfig.find_by(file_path: 'site/system/global/site.yml')&.update!(config: {})

    PostmarkService.expects(:send_newsletter_batch).with do |args|
      message = args[:messages].first
      message[:From] == 'Newsletter <noreply@example.com>'
    end.returns({ success: true, results: [{ 'ErrorCode' => 0, 'MessageID' => 'msg-1' }] })

    SendNewsletterJob.perform_now(@post.id, [ @member.id ])
  end

  test "broadcasts status update" do
    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-123' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)

    Turbo::StreamsChannel.expects(:broadcast_replace_to).with(
      "post_#{@post.id}_newsletter_status",
      target: "newsletter-status-#{@post.id}",
      partial: "admin/posts/newsletter_status",
      locals: { post: @post }
    )

    SendNewsletterJob.perform_now(@post.id, [ @member.id ])
  end

  test "handles broadcast failure gracefully" do
    mock_result = {
      success: true,
      results: [
        { 'ErrorCode' => 0, 'MessageID' => 'msg-123' }
      ]
    }
    PostmarkService.expects(:send_newsletter_batch).returns(mock_result)
    Turbo::StreamsChannel.expects(:broadcast_replace_to).raises(StandardError, 'Broadcast failed')

    # Should not raise
    assert_nothing_raised do
      SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    end
  end

  test "returns early if all members already received" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    PostmarkService.expects(:send_newsletter_batch).never

    result = SendNewsletterJob.perform_now(@post.id, [ @member.id ])
    
    assert_equal({ sent: 0, failed: 0 }, result)
  end

  test "strips HTML for text body" do
    mock_renderer = mock('renderer')
    html_content = '<p>Hello <strong>World</strong></p><br>'
    mock_renderer.expects(:render).returns(html_content)
    NewsletterRenderer.expects(:new).with(@post, @member).returns(mock_renderer)

    PostmarkService.expects(:send_newsletter_batch).with do |args|
      message = args[:messages].first
      message[:TextBody] == 'Hello World'
    end.returns({ success: true, results: [{ 'ErrorCode' => 0, 'MessageID' => 'msg-1' }] })

    SendNewsletterJob.perform_now(@post.id, [ @member.id ])
  end

  test "handles empty post title" do
    @post.update!(metadata: @post.metadata.merge('title' => nil))

    PostmarkService.expects(:send_newsletter_batch).with do |args|
      message = args[:messages].first
      message[:Subject] == 'Newsletter'
    end.returns({ success: true, results: [{ 'ErrorCode' => 0, 'MessageID' => 'msg-1' }] })

    SendNewsletterJob.perform_now(@post.id, [ @member.id ])
  end
end

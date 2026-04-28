require "test_helper"

class NewsletterSendTest < ActiveSupport::TestCase
  def setup
    @member = create(:member, email: 'subscriber@example.com')
    @post = create(:post, metadata: { "title" => "Test Newsletter", "status" => "published", "date" => "2024-01-01" })
  end

  test "valid newsletter send" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: Time.current,
      message_id: 'test-message-123'
    )
    assert ns.valid?
  end

  test "requires post_id" do
    ns = NewsletterSend.new(
      member: @member,
      sent_at: Time.current
    )
    assert_not ns.valid?
    assert_includes ns.errors[:post_id], "can't be blank"
  end

  test "requires member_id" do
    ns = NewsletterSend.new(
      post: @post,
      sent_at: Time.current
    )
    assert_not ns.valid?
    assert_includes ns.errors[:member_id], "can't be blank"
  end

  test "requires sent_at" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member
    )
    assert_not ns.valid?
    assert_includes ns.errors[:sent_at], "can't be blank"
  end

  test "enforces uniqueness per post and member" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    duplicate = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: Time.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:post_id], "already sent to this member"
  end

  test "allows same member to receive different posts" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    other_post = create(:post, metadata: { "title" => "Another Newsletter", "status" => "published", "date" => "2024-01-01" })
    ns = NewsletterSend.new(
      post: other_post,
      member: @member,
      sent_at: Time.current
    )
    assert ns.valid?
  end

  test "allows same post to be sent to different members" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    other_member = create(:member, email: 'other@example.com')
    ns = NewsletterSend.new(
      post: @post,
      member: other_member,
      sent_at: Time.current
    )
    assert ns.valid?
  end

  test "optional import association" do
    import = create(:import, status: 'completed')
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: Time.current,
      import: import
    )
    assert ns.valid?
  end

  test "recent scope orders by sent_at desc" do
    old_send = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: 2.days.ago
    )

    new_member = create(:member, email: 'new@example.com')
    new_send = NewsletterSend.create!(
      post: @post,
      member: new_member,
      sent_at: Time.current
    )

    results = NewsletterSend.recent.to_a
    assert_equal new_send, results.first
    assert_equal old_send, results.last
  end

  test "for_post scope filters by post" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    other_post = create(:post, metadata: { "title" => "Other Post", "status" => "published", "date" => "2024-01-01" })
    other_member = create(:member, email: 'other@example.com')
    NewsletterSend.create!(
      post: other_post,
      member: other_member,
      sent_at: Time.current
    )

    results = NewsletterSend.for_post(@post)
    assert_equal 1, results.count
    assert_equal @member, results.first.member
  end

  test "for_member scope filters by member" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    other_post = create(:post, metadata: { "title" => "Other Post", "status" => "published", "date" => "2024-01-01" })
    other_member = create(:member, email: 'other@example.com')
    NewsletterSend.create!(
      post: other_post,
      member: other_member,
      sent_at: Time.current
    )

    results = NewsletterSend.for_member(@member)
    assert_equal 1, results.count
    assert_equal @post, results.first.post
  end

  test "stores message_id" do
    message_id = 'msg-abc123@postmark'
    ns = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current,
      message_id: message_id
    )
    assert_equal message_id, ns.reload.message_id
  end



  test "belongs to post" do
    ns = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )
    assert_equal @post, ns.post
  end

  test "belongs to member" do
    ns = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )
    assert_equal @member, ns.member
  end

  test "destroying post destroys associated newsletter_sends" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    assert_difference 'NewsletterSend.count', -1 do
      @post.destroy
    end
  end

  test "destroying member destroys associated newsletter_sends" do
    NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    assert_difference 'NewsletterSend.count', -1 do
      @member.destroy
    end
  end

  test "can have nil message_id" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: Time.current,
      message_id: nil
    )
    assert ns.valid?
  end

  test "can have nil import" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: Time.current,
      import: nil
    )
    assert ns.valid?
  end

  test "sent_at can be in the past" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: 1.week.ago
    )
    assert ns.valid?
  end

  test "sent_at can be in the future" do
    ns = NewsletterSend.new(
      post: @post,
      member: @member,
      sent_at: 1.hour.from_now
    )
    assert ns.valid?
  end
end

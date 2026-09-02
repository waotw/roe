require "test_helper"

# The bug wasn't that failures went unlogged — they were logged. It's that
# nothing recorded them, and the admin panel counts rows. A row existed only on
# success, so forty failures out of a hundred read as "Newsletter sent to 60
# members" and the site owner never learned the rest hadn't arrived.
#
# These test the property that was missing: after a partial failure, can it be
# found out afterwards?
class NewsletterFailuresVisibleTest < ActiveJob::TestCase
  def setup
    super
    @post = create(:post, metadata: { "title" => "ZZ NL", "status" => "published",
                                      "audience" => "public", "date" => "2026-01-01" })
    @ok  = create(:member, email: "ok@example.test", name: "OK")
    @bad = create(:member, email: "bad@example.test", name: "Bad")

    PostmarkConfig.delete_all
    PostmarkConfig.current.update!(server_token: "test-token")
  end

  def teardown
    NewsletterSend.where(post: @post).delete_all
    super
  end

  def stub_postmark(results)
    PostmarkService.stubs(:send_newsletter_batch).returns({ success: true, results: results })
  end

  test "a rejected message is recorded, not just logged" do
    stub_postmark([ { "ErrorCode" => 0, "MessageID" => "m-1" },
                    { "ErrorCode" => 406, "Message" => "Inactive recipient" } ])

    SendNewsletterJob.perform_now(@post.id, [ @ok.id, @bad.id ])

    failed = NewsletterSend.for_post(@post).failed
    assert_equal 1, failed.count
    assert_equal @bad.id, failed.first.member_id
    assert_equal "Inactive recipient", failed.first.error
    assert_nil failed.first.sent_at, "a failure was never sent"
    assert failed.first.attempted_at, "but it was attempted, and when matters"
  end

  # The count the panel shows.
  test "successes and failures are counted separately" do
    stub_postmark([ { "ErrorCode" => 0, "MessageID" => "m-1" },
                    { "ErrorCode" => 300, "Message" => "Invalid email" } ])

    SendNewsletterJob.perform_now(@post.id, [ @ok.id, @bad.id ])

    assert_equal 1, NewsletterSend.for_post(@post).sent.count
    assert_equal 1, NewsletterSend.for_post(@post).failed.count,
      "counting every row is what made a partial failure look like a success"
  end

  # A whole batch that never reached Postmark: every member in it failed.
  test "a batch-level failure records every member in it" do
    PostmarkService.stubs(:send_newsletter_batch).returns({ success: false, error: "500 Server Error" })

    SendNewsletterJob.perform_now(@post.id, [ @ok.id, @bad.id ])

    failed = NewsletterSend.for_post(@post).failed
    assert_equal 2, failed.count, "the batch never arrived, so nobody received it"
    assert_equal [ "500 Server Error" ], failed.pluck(:error).uniq
    assert_equal 0, NewsletterSend.for_post(@post).sent.count
  end

  # Retrying has to reach the people who failed.
  test "a failed member is retried, a delivered one isn't" do
    PostmarkService.stubs(:send_newsletter_batch).returns({ success: false, error: "boom" })
    SendNewsletterJob.perform_now(@post.id, [ @ok.id, @bad.id ])
    assert_equal 2, NewsletterSend.for_post(@post).failed.count

    stub_postmark([ { "ErrorCode" => 0, "MessageID" => "m-1" },
                    { "ErrorCode" => 0, "MessageID" => "m-2" } ])
    SendNewsletterJob.perform_now(@post.id, [ @ok.id, @bad.id ])

    assert_equal 2, NewsletterSend.for_post(@post).sent.count,
      "skipping anyone with a row would have skipped everyone who failed"
    assert_equal 0, NewsletterSend.for_post(@post).failed.count,
      "a member who then succeeds shouldn't stay marked failed"
  end

  test "an already-delivered member is not sent to twice" do
    stub_postmark([ { "ErrorCode" => 0, "MessageID" => "m-1" } ])
    SendNewsletterJob.perform_now(@post.id, [ @ok.id ])

    PostmarkService.expects(:send_newsletter_batch).never
    SendNewsletterJob.perform_now(@post.id, [ @ok.id ])

    assert_equal 1, NewsletterSend.for_post(@post).sent.count
  end
end

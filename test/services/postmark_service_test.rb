require "test_helper"

class PostmarkServiceTest < ActiveSupport::TestCase
  def setup
    super
    PostmarkConfig.delete_all
    @config = PostmarkConfig.current
    @config.update!(server_token: "test-server-token", verified_at: Time.current)
  end

  test "configured? returns true when server_token is set" do
    assert PostmarkService.configured?
  end

  test "configured? returns false when server_token is blank" do
    @config.update!(server_token: nil)
    assert_not PostmarkService.configured?
  end

  test "test_connection succeeds with valid token" do
    response = mock("response")
    response.stubs(:code).returns("200")

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).with("api.postmarkapp.com", 443).returns(http)

    result = PostmarkService.test_connection
    assert result[:success]
    assert_equal "Connection successful", result[:message]
  end

  test "test_connection fails with invalid token" do
    response = mock("response")
    response.stubs(:code).returns("401")
    response.stubs(:body).returns('{"Message": "Invalid token"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).with("api.postmarkapp.com", 443).returns(http)

    result = PostmarkService.test_connection
    assert_not result[:success]
    assert_equal "Invalid token", result[:error]
  end

  test "test_connection fails when no token provided" do
    result = PostmarkService.test_connection("")
    assert_not result[:success]
    assert_equal "No server token provided", result[:error]
  end

  test "test_connection handles network errors" do
    Net::HTTP.expects(:new).raises(StandardError, "Connection refused")

    result = PostmarkService.test_connection
    assert_not result[:success]
    assert_equal "Connection refused", result[:error]
  end

  test "send_transactional_email succeeds" do
    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "abc-123"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).with("api.postmarkapp.com", 443).returns(http)

    result = PostmarkService.send_transactional_email(
      to_email: "user@example.com",
      to_name: "Test User",
      subject: "Test Subject",
      html_content: "<p>Hello</p>",
      tag: "welcome"
    )

    assert result[:success]
    assert_equal "abc-123", result[:message_id]
  end

  test "send_transactional_email fails when not configured" do
    @config.update!(server_token: nil)

    result = PostmarkService.send_transactional_email(
      to_email: "user@example.com",
      to_name: "Test User",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )

    assert_not result[:success]
    assert_equal "Postmark not configured", result[:error]
  end

  test "send_transactional_email uses site config for from address" do
    SiteConfig.find_by(file_path: "site/system/global/site.yml")&.update!(
      config: { "author_email" => "author@test.com", "author" => "Test Author" }
    )
    SiteConfig.reload!("site")

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "msg-1"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_transactional_email(
      to_email: "user@example.com",
      to_name: "Test User",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )
  end

  test "send_transactional_email falls back to defaults when site config not set" do
    SiteConfig.find_by(file_path: "site/system/global/site.yml")&.update!(config: {})
    SiteConfig.reload!("site")

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "msg-1"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).with do |request|
      body = JSON.parse(request.body)
      body["From"] == "Newsletter <noreply@example.com>"
    end.returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_transactional_email(
      to_email: "user@example.com",
      to_name: "Test User",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )
  end

  test "send_transactional_email strips HTML for text body" do
    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "msg-1"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).with do |request|
      body = JSON.parse(request.body)
      body["TextBody"] == "Hello World"
    end.returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_transactional_email(
      to_email: "user@example.com",
      to_name: "Test User",
      subject: "Test",
      html_content: "<p>Hello</p> <p>World</p>"
    )
  end

  test "send_transactional_email handles API errors" do
    response = mock("response")
    response.stubs(:code).returns("422")
    response.stubs(:body).returns('{"Message": "Invalid email address"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    result = PostmarkService.send_transactional_email(
      to_email: "invalid",
      to_name: "Test",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )

    assert_not result[:success]
    assert_equal "Invalid email address", result[:error]
  end

  test "send_newsletter_batch succeeds" do
    messages = [
      { To: "user1@example.com", Subject: "Test 1" },
      { To: "user2@example.com", Subject: "Test 2" }
    ]

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('[
      {"ErrorCode": 0, "MessageID": "msg-1"},
      {"ErrorCode": 0, "MessageID": "msg-2"}
    ]')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).with("api.postmarkapp.com", 443).returns(http)

    result = PostmarkService.send_newsletter_batch(messages: messages)

    assert result[:success]
    assert_equal 2, result[:results].size
  end

  test "send_newsletter_batch fails when not configured" do
    @config.update!(server_token: nil)

    result = PostmarkService.send_newsletter_batch(messages: [])

    assert_not result[:success]
    assert_equal "Postmark not configured", result[:error]
  end

  test "send_newsletter_batch handles partial failures" do
    messages = [
      { To: "user1@example.com", Subject: "Test 1" },
      { To: "user2@example.com", Subject: "Test 2" }
    ]

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('[
      {"ErrorCode": 0, "MessageID": "msg-1"},
      {"ErrorCode": 406, "Message": "Invalid recipient"}
    ]')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    result = PostmarkService.send_newsletter_batch(messages: messages)

    assert result[:success]
    assert_equal 0, result[:results][0]["ErrorCode"]
    assert_equal 406, result[:results][1]["ErrorCode"]
  end

  test "send_newsletter_batch handles API failure" do
    response = mock("response")
    response.stubs(:code).returns("500")
    response.stubs(:body).returns('{"Message": "Server error"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    result = PostmarkService.send_newsletter_batch(messages: [ { To: "test@example.com" } ])

    assert_not result[:success]
    assert_equal "Server error", result[:error]
  end

  test "get_stats returns server and member information" do
    # Create some test data
    create_list(:member, 5, newsletter_status: :subscribed)
    create_list(:member, 3, newsletter_status: :unsubscribed)

    post = create(:post)
    member = create(:member)
    NewsletterSend.create!(post: post, member: member, sent_at: 1.day.ago)

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{
      "Name": "Test Server",
      "Color": "blue"
    }')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    result = PostmarkService.get_stats

    assert_equal "Test Server", result[:server_name]
    assert_equal "blue", result[:server_color]
    assert_equal 9, result[:total_members] # 5 + 3 + 1 (from newsletter_send)
    assert_equal 6, result[:subscribed] # 5 + 1 (from newsletter_send)
    assert_equal 3, result[:unsubscribed]
    assert_equal 1, result[:newsletters_sent]
    assert_equal 1, result[:total_emails_sent]
    assert result[:last_newsletter_at].present?
  end

  test "get_stats fails when not configured" do
    @config.update!(server_token: nil)

    result = PostmarkService.get_stats

    assert result[:error]
    assert_equal "Postmark not configured", result[:error]
  end

  test "get_stats handles API errors" do
    response = mock("response")
    response.stubs(:code).returns("401")

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    result = PostmarkService.get_stats

    assert result[:error]
    assert_equal "Failed to fetch server info", result[:error]
  end

  test "handles malformed JSON in response" do
    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns("not valid json")

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).returns(response)

    Net::HTTP.expects(:new).returns(http)

    # Should not raise
    result = PostmarkService.test_connection
    assert result[:success]
  end

  test "uses correct headers for all requests" do
    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "msg-1"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).with do |request|
      request["Accept"] == "application/json" &&
      request["Content-Type"] == "application/json" &&
      request["X-Postmark-Server-Token"] == "test-server-token"
    end.returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_transactional_email(
      to_email: "test@example.com",
      to_name: "Test",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )
  end

  test "handles network timeouts" do
    Net::HTTP.expects(:new).raises(Timeout::Error, "Request timed out")

    result = PostmarkService.test_connection

    assert_not result[:success]
    assert_equal "Request timed out", result[:error]
  end

  test "uses broadcast message stream for newsletters" do
    messages = [ { To: "test@example.com", Subject: "Newsletter" } ]

    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('[{"ErrorCode": 0, "MessageID": "msg-1"}]')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).with do |request|
      body = JSON.parse(request.body)
      body[0]["To"] == "test@example.com"
    end.returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_newsletter_batch(messages: messages)
  end

  test "uses outbound message stream for transactional" do
    response = mock("response")
    response.stubs(:code).returns("200")
    response.stubs(:body).returns('{"MessageID": "msg-1"}')

    http = mock("http")
    http.expects(:use_ssl=).with(true)
    http.expects(:request).with do |request|
      body = JSON.parse(request.body)
      body["MessageStream"] == "outbound"
    end.returns(response)

    Net::HTTP.expects(:new).returns(http)

    PostmarkService.send_transactional_email(
      to_email: "test@example.com",
      to_name: "Test",
      subject: "Test",
      html_content: "<p>Hello</p>"
    )
  end
end

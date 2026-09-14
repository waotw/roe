class PostmarkService
  API_BASE = "https://api.postmarkapp.com"

  class << self
    def configured?
      PostmarkConfig.configured?
    end

    def test_connection(server_token = nil)
      token = server_token || PostmarkConfig.current.server_token
      return { success: false, error: "No server token provided" } if token.blank?

      # Test by getting account info
      uri = URI("#{API_BASE}/server")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.path)
      request["Accept"] = "application/json"
      request["X-Postmark-Server-Token"] = token

      response = http.request(request)

      if response.code == "200"
        # The body identifies the server, including DeliveryType ("Live" or
        # "Sandbox"). A sandbox server records a message without delivering it,
        # which changes what we can honestly tell someone after a test send —
        # so keep the data rather than throwing it away.
        data = JSON.parse(response.body) rescue {}
        { success: true, message: "Connection successful", server: data }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: error_data["Message"] || response.body }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def send_transactional_email(to_email:, to_name:, subject:, html_content:, tag: nil)
      return { success: false, error: "Postmark not configured" } unless configured?

      # No stand-in address: Postmark rejects an unverified From, so sending
      # from a made-up one fails anyway, with a worse error. See SiteSender.
      return { success: false, error: SiteSender::MISSING } unless SiteSender.configured?

      config = PostmarkConfig.current
      from = SiteSender.from_header

      Rails.logger.info "📤 Sending from: #{from}"

      uri = URI("#{API_BASE}/email")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-Postmark-Server-Token"] = config.server_token

      body = {
        From: from,
        To: "#{to_name} <#{to_email}>",
        Subject: subject,
        HtmlBody: html_content,
        TextBody: strip_html(html_content),
        MessageStream: "outbound"
      }
      body[:Tag] = tag if tag.present?

      request.body = body.to_json

      Rails.logger.info "🌐 Sending to Postmark API..."
      response = http.request(request)
      Rails.logger.info "📡 Response Code: #{response.code}"
      Rails.logger.info "📡 Response Body: #{response.body}"

      if response.code == "200"
        data = JSON.parse(response.body)
        Rails.logger.info "📊 Parsed data: #{data.inspect}"
        { success: true, message_id: data["MessageID"] }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false,
          error: error_data["Message"] || response.body,
          error_code: error_data["ErrorCode"] }
      end
    rescue => e
      Rails.logger.error "Postmark transactional send failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end

    def send_newsletter_batch(messages:)
      return { success: false, error: "Postmark not configured" } unless configured?

      config = PostmarkConfig.current

      # Postmark batch API endpoint
      uri = URI("#{API_BASE}/email/batch")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-Postmark-Server-Token"] = config.server_token

      request.body = messages.to_json

      response = http.request(request)

      if response.code == "200"
        data = JSON.parse(response.body)
        { success: true, results: data }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: error_data["Message"] || response.body }
      end
    rescue => e
      Rails.logger.error "Postmark batch send failed: #{e.message}"
      { success: false, error: e.message }
    end

    def get_stats
      return { error: "Postmark not configured" } unless configured?

      config = PostmarkConfig.current

      # Get server info from Postmark
      uri = URI("#{API_BASE}/server")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.path)
      request["Accept"] = "application/json"
      request["X-Postmark-Server-Token"] = config.server_token

      response = http.request(request)

      if response.code == "200"
        server_data = JSON.parse(response.body)

        {
          server_name: server_data["Name"],
          server_color: server_data["Color"],
          total_members: Member.count,
          subscribed: Member.newsletter_subscribed.count,
          unsubscribed: Member.newsletter_unsubscribed.count,
          newsletters_sent: NewsletterSend.select(:post_id).distinct.count,
          total_emails_sent: NewsletterSend.count,
          last_newsletter_at: NewsletterSend.maximum(:sent_at)
        }
      else
        { error: "Failed to fetch server info" }
      end
    rescue => e
      Rails.logger.error "Failed to get Postmark stats: #{e.message}"
      { error: e.message }
    end

    private

    def strip_html(html)
      html.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
    end
  end
end

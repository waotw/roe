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

    # Whether a webhook aimed at `url` is registered on this server, across both
    # the outbound and broadcast streams — a live, read-only check (no send).
    # Used by the settings status to confirm the account-setup webhook is in
    # place. Any API failure reads as "can't confirm" (false), never raises.
    def webhook_for_url?(server_token, url)
      webhook_ids_for_url(server_token, url).any?
    rescue => e
      Rails.logger.warn "Postmark webhook lookup failed: #{e.message}"
      false
    end

    # Verify every Roe webhook on this server (the ones pointing at `url`, across
    # both streams) using Postmark's own on-demand check: POST /webhooks/{id}/
    # verify makes Postmark POST a test of each enabled event type (Delivery,
    # Bounce, SpamComplaint) to our endpoint and report whether each returned a
    # 200 — synchronously, no email, DKIM-independent. This is exactly the "Send
    # test" button in Postmark's own UI, over the API.
    #
    # Returns { ok:, results: [{ id:, success:, message: }], error: }. ok is true
    # only when a webhook was found AND every one verified. Never raises.
    def verify_webhooks(server_token, url)
      return { ok: false, error: "No server token" } if server_token.blank?
      return { ok: false, error: "No webhook URL for this environment" } if url.blank?

      ids = webhook_ids_for_url(server_token, url)
      return { ok: false, error: "No webhook is registered for this site yet" } if ids.empty?

      results = ids.map { |id| verify_one_webhook(server_token, id) }
      { ok: results.all? { |r| r[:success] }, results: results }
    rescue => e
      Rails.logger.warn "Postmark webhook verify failed: #{e.message}"
      { ok: false, error: e.message }
    end

    private

    # IDs of webhooks on this server (both streams) whose Url matches ours.
    def webhook_ids_for_url(server_token, url)
      return [] if server_token.blank? || url.blank?

      %w[outbound broadcast].flat_map do |stream|
        data = postmark_get("/webhooks?MessageStream=#{stream}", server_token)
        Array(data["Webhooks"]).select { |w| w["Url"] == url }.map { |w| w["ID"] }
      end.uniq
    end

    # POST /webhooks/{id}/verify — a 200 means the check RAN, not that it passed;
    # the body's Success field is the answer (see Postmark docs).
    def verify_one_webhook(server_token, id)
      data = postmark_post("/webhooks/#{id}/verify", server_token)
      { id: id, success: data["Success"] == true, message: data["Message"] }
    end

    def postmark_get(path, server_token)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["X-Postmark-Server-Token"] = server_token
      response = http.request(request)
      JSON.parse(response.body) rescue {}
    end

    def postmark_post(path, server_token)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["X-Postmark-Server-Token"] = server_token
      response = http.request(request)
      JSON.parse(response.body) rescue {}
    end

    def strip_html(html)
      html.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
    end
  end
end

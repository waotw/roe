class MailjetService
  class << self
    def configured?
      MailjetConfig.configured?
    end

    def ensure_contact_properties
      configure_client

      required_properties = [
        { name: 'tier', datatype: 'str' },
        { name: 'status', datatype: 'str' },
        { name: 'subscribed_at', datatype: 'str' }
      ]

      # Get existing properties
      existing = Mailjet::Contactmetadata.all.map { |p| p.name.downcase }

      # Create missing properties
      required_properties.each do |prop|
        unless existing.include?(prop[:name])
          Mailjet::Contactmetadata.create(
            name: prop[:name],
            datatype: prop[:datatype],
            namespace: 'static'
          )
          Rails.logger.info "Created Mailjet contact property: #{prop[:name]}"
        end
      end

      { success: true }
    rescue => e
      Rails.logger.error "Failed to create contact properties: #{e.message}"
      { success: false, error: e.message }
    end

    def test_connection(api_key = nil, secret_key = nil)
      # Use provided keys or stored config
      if api_key.nil? || secret_key.nil?
        config = MailjetConfig.current
        api_key = config.api_key
        secret_key = config.secret_key
      end

      return { success: false, error: "No API credentials provided" } if api_key.blank? || secret_key.blank?

      configure_client(api_key, secret_key)

      # Test by fetching account info
      response = Mailjet::Contact.all(limit: 1)

      { success: true, message: "Connection successful" }
    rescue Mailjet::ApiError => e
      { success: false, error: "API Error: #{e.message}" }
    rescue => e
      { success: false, error: e.message }
    end

    def sync_member(member)
      return { success: false, error: "Mailjet not configured" } unless configured?

      configure_client

      if member.mailjet_contact_id.present?
        update_contact(member)
      else
        create_contact(member)
      end
    rescue Mailjet::ApiError => e
      Rails.logger.error "Mailjet API Error for #{member.email}: #{e.message}"
      { success: false, error: e.message }
    rescue => e
      Rails.logger.error "Mailjet Error for #{member.email}: #{e.message}"
      { success: false, error: e.message }
    end

    def send_newsletter(to_email:, to_name:, subject:, html_content:)
      return { success: false, error: "Mailjet not configured" } unless configured?

      config = MailjetConfig.current
      from_email = SiteConfig.current('site')&.config&.dig('author_email') || 'noreply@example.com'
      from_name = SiteConfig.current('site')&.config&.dig('author') || 'Newsletter'

      uri = URI('https://api.mailjet.com/v3.1/send')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.basic_auth(config.api_key, config.secret_key)

      request.body = {
        Messages: [{
          From: { Email: from_email, Name: from_name },
          To: [{ Email: to_email, Name: to_name }],
          Subject: subject,
          HTMLPart: html_content,
          TextPart: strip_html(html_content)
        }]
      }.to_json

      response = http.request(request)

      if response.code == '200'
        data = JSON.parse(response.body)
        { success: true, message_id: data.dig('Messages', 0, 'To', 0, 'MessageID') }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: error_data['ErrorMessage'] || response.body }
      end
    rescue => e
      Rails.logger.error "Mailjet send failed: #{e.message}"
      { success: false, error: e.message }
    end

    def send_newsletter_bulk(messages:)
      return { success: false, error: "Mailjet not configured" } unless configured?

      # DRY RUN MODE - Simulate sending without calling API
      if ENV['NEWSLETTER_DRY_RUN'] == 'true'
        Rails.logger.info "🧪 DRY RUN: Would send #{messages.size} emails"

        # Simulate API response
        fake_results = messages.map.with_index do |msg, i|
          {
            'Status' => 'success',
            'To' => [{
              'Email' => msg[:To][0][:Email],
              'MessageID' => "dry-run-#{Time.current.to_i}-#{i}",
              'MessageUUID' => SecureRandom.uuid
            }]
          }
        end

        # Simulate realistic API delay (20ms per email)
        sleep(messages.size * 0.02)

        return { success: true, results: fake_results }
      end

      # REAL MODE - Actually send via Mailjet
      config = MailjetConfig.current

      uri = URI('https://api.mailjet.com/v3.1/send')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.basic_auth(config.api_key, config.secret_key)

      request.body = { Messages: messages }.to_json

      response = http.request(request)

      if response.code == '200'
        data = JSON.parse(response.body)
        { success: true, results: data['Messages'] }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: error_data['ErrorMessage'] || response.body }
      end
    rescue => e
      Rails.logger.error "Mailjet bulk send failed: #{e.message}"
      { success: false, error: e.message }
    end

    # def send_newsletter(to_email:, to_name:, subject:, html_content:)
    #   return { success: false, error: "Mailjet not configured" } unless configured?

    #   configure_client

    #   # Get sender email from config
    #   from_email = SiteConfig.current('site')&.config&.dig('author_email') || 'noreply@example.com'
    #   from_name = SiteConfig.current('site')&.config&.dig('author') || SiteConfig.current('site')&.config&.dig('title') || 'Newsletter'

    #   # Send via Mailjet Send API v3.1
    #   response = Mailjet::Send.create(
    #     Messages: [{
    #       From: {
    #         Email: from_email,
    #         Name: from_name
    #       },
    #       To: [{
    #         Email: to_email,
    #         Name: to_name
    #       }],
    #       Subject: subject,
    #       HTMLPart: html_content,
    #       TextPart: strip_html(html_content) # Plain text fallback
    #     }]
    #   )

    #   if response.success?
    #     message_id = response.dig(0, 'To', 0, 'MessageID')
    #     { success: true, message_id: message_id }
    #   else
    #     { success: false, error: "Failed to send email" }
    #   end
    # rescue Mailjet::ApiError => e
    #   Rails.logger.error "Mailjet Send API Error: #{e.message}"
    #   { success: false, error: "Mailjet API Error: #{e.message}" }
    # rescue => e
    #   Rails.logger.error "Failed to send newsletter: #{e.message}"
    #   { success: false, error: e.message }
    # end

    def create_contact(member)
      configure_client

      # Split name into first and last
      name_parts = member.name.to_s.split(' ', 2)
      first_name = name_parts[0] || ''
      last_name = name_parts[1] || ''

      # Mailjet's API for creating/updating contacts
      contact = Mailjet::Contact.create(
        email: member.email,
        name: last_name,  # Mailjet uses 'name' for last name
        is_excluded_from_campaigns: !member.newsletter_subscribed?
      )

      if contact.present? && contact.id
        member.update_column(:mailjet_contact_id, contact.id.to_s)

        # Add properties (custom fields + firstname)
        update_contact_properties(contact.id, member, first_name)

        { success: true, contact_id: contact.id }
      else
        { success: false, error: "Failed to create contact" }
      end
    rescue Mailjet::ApiError => e
      # Contact might already exist
      if e.message.include?("already exists") || e.message.include?("MJ18")
        # Try to find existing contact
        existing = find_contact_by_email(member.email)
        if existing
          member.update_column(:mailjet_contact_id, existing['ID'].to_s)
          update_contact(member)
        else
          { success: false, error: "Contact exists but couldn't be retrieved" }
        end
      else
        raise
      end
    end

    def update_contact(member)
      configure_client

      return create_contact(member) if member.mailjet_contact_id.blank?

      # Split name into first and last
      name_parts = member.name.to_s.split(' ', 2)
      first_name = name_parts[0] || ''
      last_name = name_parts[1] || ''

      contact = Mailjet::Contact.find(member.mailjet_contact_id)

      contact.update_attributes(
        name: last_name,
        is_excluded_from_campaigns: !member.newsletter_subscribed?
      )

      # Update properties
      update_contact_properties(member.mailjet_contact_id, member, first_name)

      { success: true, contact_id: member.mailjet_contact_id }
    rescue Mailjet::ApiError => e
      if e.message.include?("not found")
        # Contact was deleted, recreate
        member.update_column(:mailjet_contact_id, nil)
        create_contact(member)
      else
        raise
      end
    end

    def unsubscribe_contact(member)
      configure_client

      return { success: false, error: "No Mailjet contact ID" } if member.mailjet_contact_id.blank?

      contact = Mailjet::Contact.find(member.mailjet_contact_id)
      contact.update_attributes(is_excluded_from_campaigns: true)

      member.unsubscribe_from_newsletter!

      { success: true }
    rescue => e
      Rails.logger.error "Failed to unsubscribe #{member.email}: #{e.message}"
      { success: false, error: e.message }
    end

    def find_contact_by_email(email)
      configure_client

      contacts = Mailjet::Contact.all(limit: 1, contact_email: email)
      contacts.first
    rescue => e
      Rails.logger.error "Failed to find contact #{email}: #{e.message}"
      nil
    end

    def get_stats
      configure_client

      {
        total_members: Member.count,
        mailjet_total: Mailjet::Contact.count,
        synced_members: Member.where.not(mailjet_contact_id: nil).count,
        unsynced_members: Member.where(mailjet_contact_id: nil).count,
        subscribed: Member.newsletter_subscribed.count,
        unsubscribed: Member.newsletter_unsubscribed.count
      }
    rescue => e
      Rails.logger.error "Failed to get Mailjet stats: #{e.message}"
      { error: e.message }
    end

    private

    def configure_client(api_key = nil, secret_key = nil)
      if api_key.nil? || secret_key.nil?
        config = MailjetConfig.current
        api_key ||= config.api_key
        secret_key ||= config.secret_key
      end

      Mailjet.configure do |config|
        config.api_key = api_key
        config.secret_key = secret_key
        config.api_version = "v3.1"
        config.default_from = SiteConfig.get('author_email') || 'noreply@example.com'
      end
    end

    def update_contact_properties(contact_id, member, first_name = nil)
      # Extract first name if not provided
      if first_name.nil?
        name_parts = member.name.to_s.split(' ', 2)
        first_name = name_parts[0] || ''
      end

      # Set firstname first (built-in property)
      Mailjet::Contactdata.find(contact_id).update_attributes(
        data: [{ Name: "firstname", Value: first_name }]
      )

      # Then set custom properties in separate calls
      Mailjet::Contactdata.find(contact_id).update_attributes(
        data: [{ Name: "tier", Value: member.tier }]
      )

      Mailjet::Contactdata.find(contact_id).update_attributes(
        data: [{ Name: "status", Value: member.status }]
      )

      Mailjet::Contactdata.find(contact_id).update_attributes(
        data: [{ Name: "subscribed_at", Value: member.subscribed_at&.iso8601 }]
      )
    end

    def strip_html(html)
      # Simple HTML stripping for plain text version
      html.gsub(/<[^>]*>/, '').gsub(/\s+/, ' ').strip
    end
  end
end

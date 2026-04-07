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
  end
end

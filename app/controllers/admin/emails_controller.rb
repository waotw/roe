class Admin::EmailsController < Admin::BaseController
  TEMPLATES = {
    'magic_link' => {
      name: 'Send Sign In Link',
      variables: ['@member_name', '@member_email', '@magic_link', '@site_name']
    },
    'welcome' => {
      name: 'Welcome New Member',
      variables: ['@member_name', '@member_email', '@site_name']
    },
    'upgrade_success' => {
      name: 'Confirm Paid Upgrade',
      variables: ['@member_name', '@member_email', '@password', '@site_name', '@account_url']
    },
    'email_changed' => {
      name: 'Confirm Email Change',
      variables: ['@member_name', '@new_email', '@old_email', '@site_name']
    },
    'membership_cancelled' => {
      name: 'Membership Cancelled',
      variables: ['@member_name', '@member_email', '@site_name']
    },
    'email_confirmation' => {
      name: 'Confirm Email Address',
      variables: ['@member_name', '@confirmation_link', '@site_name']
    },
    'payment_failed' => {
      name: 'Payment Failed',
      variables: ['@member_name', '@member_email', '@update_payment_url', '@site_name']
    },
    'account_deletion' => {
      name: 'Account Deleted',
      variables: ['@member_name', '@member_email', '@site_name']
    }
  }.freeze

  def index
    emails_dir = Rails.root.join('site', 'emails')

    @emails = if Dir.exist?(emails_dir)
      Dir.glob(emails_dir.join('*.md')).map do |file_path|
        filename = File.basename(file_path, '.md')
        template_info = TEMPLATES[filename]

        {
          filename: filename,
          name: template_info ? template_info[:name] : filename.split(/[-_]/).map(&:capitalize).join(' '),
          path: file_path
        }
      end.sort_by { |e| e[:filename] }
    else
      []
    end

    @title = "Email Templates"
    @description = "Manage transactional email templates sent to members."
  end

  def edit
    @filename = params[:id]
    @file_path = Rails.root.join('site', 'emails', "#{@filename}.md")

    unless File.exist?(@file_path)
      flash[:error] = "Email template not found"
      redirect_to admin_emails_path and return
    end

    @content = File.read(@file_path)

    template_info = TEMPLATES[@filename]
    @template_name = template_info ? template_info[:name] : @filename.split('-').map(&:capitalize).join(' ')
    @available_variables = template_info ? template_info[:variables] : []

    @preview_path = preview_admin_email_path(@filename)
  end

  def update
    @filename = params[:id]
    @file_path = Rails.root.join('site', 'emails', "#{@filename}.md")

    unless File.exist?(@file_path)
      flash[:error] = "Email template not found"
      redirect_to admin_emails_path and return
    end

    content = params[:content]
    normalized = content.gsub(/\r\n/, "\n")

    File.write(@file_path, normalized)

    flash[:notice] = "Email template saved"
    redirect_to edit_admin_email_path(@filename)
  end

  def preview
    @filename = params[:id]
    @file_path = Rails.root.join('site', 'emails', "#{@filename}.md")

    # Use submitted content for POST, saved content for GET
    content = if request.post?
      params[:content]
    else
      File.exist?(@file_path) ? File.read(@file_path) : "Template not found"
    end

    # Replace variables with example data
    preview_variables = {
      'member_name' => 'Jane Doe',
      'member_email' => 'jane@example.com',
      'magic_link' => 'https://yoursite.com/auth/verify/zen-mountain-haiku-42',
      'confirmation_url' => 'https://yoursite.com/confirm-email/crystal-river-sunset-73',
      'site_name' => SiteConfig.get('site.title') || 'Your Site',
      'password' => 'smooth-river-dawn-17',
      'account_url' => "#{request.base_url}/account",
      'update_payment_url' => "#{request.base_url}/account/payment",
      'new_email' => 'jane.new@example.com',
      'old_email' => 'jane.old@example.com'
    }

    preview_variables.each do |key, value|
      content.gsub!("@#{key}", value.to_s)
    end

    # Render with EmailRenderer
    @preview_html = EmailRenderer.render_content(content)
    @preview_mode = true
    @preview_id = "email-#{@filename}"

    render layout: false
  end
end

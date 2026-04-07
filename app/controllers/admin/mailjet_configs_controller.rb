class Admin::MailjetConfigsController < Admin::BaseController
  def edit
    @mailjet_config = MailjetConfig.current
  end

  def update
    @mailjet_config = MailjetConfig.current

    # Get the values from params
    api_key = params[:mailjet_config][:api_key]
    secret_key = params[:mailjet_config][:secret_key]

    # Skip if they're the masked placeholders
    api_key = nil if api_key == '••••••••••••••••'
    secret_key = nil if secret_key == '••••••••••••••••'

    # Test credentials if provided
    if api_key.present? && secret_key.present?
      test_result = MailjetService.test_connection(api_key, secret_key)

      unless test_result[:success]
        flash[:error] = "Failed to connect to Mailjet: #{test_result[:error]}"
        redirect_to edit_admin_mailjet_config_path and return
      end
    end

    # Update only if values are provided
    update_params = {}
    update_params[:api_key] = api_key if api_key.present?
    update_params[:secret_key] = secret_key if secret_key.present?

    # Use direct assignment to trigger custom setters
    update_params.each do |key, value|
      @mailjet_config.public_send("#{key}=", value)
    end

    if @mailjet_config.save
      # Ensure contact properties exist in Mailjet
      MailjetService.ensure_contact_properties

      flash[:notice] = "Mailjet configuration saved successfully"
      redirect_to edit_admin_mailjet_config_path
    else
      flash.now[:error] = "Failed to save Mailjet configuration"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mailjet_config = MailjetConfig.current
    @mailjet_config.disconnect!

    flash[:notice] = "Mailjet disconnected"
    redirect_to edit_admin_mailjet_config_path
  end

  def sync_all
    unless MailjetConfig.configured?
      flash[:error] = "Mailjet is not configured"
      redirect_to edit_admin_mailjet_config_path and return
    end

    # Queue all members for sync
    Member.find_each do |member|
      SyncMemberToMailjetJob.perform_later(member.id)
    end

    flash[:notice] = "Queued #{Member.count} members for sync. This may take a few minutes."
    redirect_to edit_admin_mailjet_config_path
  end
end

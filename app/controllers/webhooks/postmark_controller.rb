class Webhooks::PostmarkController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_token

  def create
    # Queue background job to process the webhook
    ProcessPostmarkWebhookJob.perform_later(webhook_params.to_h)

    head :ok
  rescue => e
    Rails.logger.error "Postmark webhook error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :ok # Always return 200 to prevent Postmark retries
  end

  private

  def verify_webhook_token
    config = PostmarkConfig.current
    provided_token = params[:token]

    unless provided_token == config.webhook_token
      Rails.logger.warn "Invalid Postmark webhook token attempt"
      head :unauthorized
    end
  end

  def webhook_params
    params.permit(
      :RecordType,
      :MessageStream,
      :MessageID,
      :Recipient,
      :Email,
      :From,
      :BouncedAt,
      :DeliveredAt,
      :Type,
      :TypeCode,
      :Name,
      :Tag,
      :Description,
      :Details,
      :Subject
    )
  end
end

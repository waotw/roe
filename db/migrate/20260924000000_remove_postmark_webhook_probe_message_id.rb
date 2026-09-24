class RemovePostmarkWebhookProbeMessageId < ActiveRecord::Migration[8.1]
  # The email-probe webhook check (send a test email, wait for the matching
  # Delivery callback, record its MessageID) is gone — replaced by Postmark's
  # own on-demand verification (POST /webhooks/{id}/verify), which is
  # synchronous and needs no stored MessageID. webhook_verified_at is still
  # used (it records the last successful verification); only this column is dead.
  def change
    remove_column :postmark_configs, :webhook_probe_message_id, :string
  end
end

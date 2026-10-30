class AddAccountSetupToPostmarkConfigs < ActiveRecord::Migration[8.1]
  # Postmark Account-API setup ("Have Roe set up your Postmark integration").
  #
  # account_token: an Account API token can Manage Servers and read Sender
  #   Signatures — a much larger blast radius than a Server token. It's kept
  #   ONLY in production (encrypted via the model's `encrypts`), where the box
  #   is a controlled server and the token can't be read back from the admin
  #   UI; keeping it there powers the pre-emptive sender-signature check. Local
  #   never writes this column — it uses the token in-request and discards it.
  #
  # webhook_probe_message_id / webhook_verified_at: setting up the webhook is
  #   only half the job; Roe confirms it *works* by sending a probe email and
  #   waiting for the matching Delivery callback. The probe's MessageID is
  #   recorded on send; the webhook handler stamps webhook_verified_at when the
  #   Delivery event for that id arrives, closing the loop.
  def change
    add_column :postmark_configs, :account_token, :text
    add_column :postmark_configs, :webhook_probe_message_id, :string
    add_column :postmark_configs, :webhook_verified_at, :datetime
  end
end

class AddSenderVerificationToPostmarkConfigs < ActiveRecord::Migration[8.1]
  # Whether Postmark will accept the site's From address is a separate question
  # from whether the server token works, and the only way to ask it is to
  # attempt a send — listing Sender Signatures needs an Account API token, and
  # Roe only holds a Server token.
  #
  # The address is stored rather than a status, so "is it verified" is just
  # "does this match the current author_email". Changing the address makes it
  # unverified on its own, with no reset hook to wire up or keep in step.
  def change
    add_column :postmark_configs, :sender_verified_address, :string
    add_column :postmark_configs, :sender_error, :text
  end
end

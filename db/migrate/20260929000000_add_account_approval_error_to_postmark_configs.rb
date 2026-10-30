# Records Postmark's "account pending approval" state (ErrorCode 412), captured
# when a real send is refused because the account can only reach same-domain
# recipients yet. Mirrors sender_error: a wild failure the operator can't
# otherwise see becomes a status-page warning. Cleared on the next successful
# send. account_approval_error holds Postmark's verbatim message.
class AddAccountApprovalErrorToPostmarkConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :postmark_configs, :account_approval_error, :text
  end
end

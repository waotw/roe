class SyncMemberToMailjetJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(member_id)
    member = Member.find_by(id: member_id)
    return unless member

    result = MailjetService.sync_member(member)

    unless result[:success]
      Rails.logger.error "Failed to sync member #{member.email} to Mailjet: #{result[:error]}"
    end
  end
end

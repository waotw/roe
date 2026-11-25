# Another page (or product) at the same address: the url_name it ends up
# with — set, or worked out from the title — is already another one's. Only
# one of the two can be reached. Advisory, like Post.conflicting_post:
# nothing stops a save.
#
# Products in the same group share an address on purpose (the variants of
# one product), so they don't count.
module UrlNameClash
  module_function

  # The other record using `value`, or nil. `except_id`: the record being
  # edited.
  def find(model, value, except_id: nil)
    value = value.to_s.strip
    return nil if value.blank?

    own = except_id.present? ? model.find_by(id: except_id) : nil
    group = own.respond_to?(:group) ? own.group.to_s.strip.presence : nil

    model.select(:id, :metadata, :file_path).find do |record|
      next false if record.id.to_s == except_id.to_s
      next false if group && record.respond_to?(:group) && record.group.to_s.strip == group

      record.url_name.to_s == value
    end
  end
end

# frozen_string_literal: true

# Keeps a renamed address working. When a published post, page or product gets
# a new url_name (or a new title, when it has no url_name of its own), the
# editor asks first: "Save new URL & redirect" sends create_redirect_from with
# the save, and this writes a 301 from the old address to the new one into
# redirects.yml (RedirectManager), which Site Sync carries to the other site.
#
# The old address is taken from the record as it was before the save, not
# from the browser: the field only says "yes, add the redirect". Both sides
# must be published — a draft never had an address worth keeping.
#
# Usage, in a controller's update:
#   old_address = rename_redirect_source(@page)   # before writing the file
#   ...write and sync...
#   add_rename_redirect(Page, old_address, metadata, @page.file_path)
module RenameRedirect
  extend ActiveSupport::Concern

  private

  # The record's public address right now, or nil when there's nothing to
  # protect: it isn't published, or it's the home page ("/" is never
  # redirected away).
  def rename_redirect_source(record)
    return nil unless record.published?

    address = record.public_url
    address == "/" ? nil : address
  end

  # Writes the 301 when the editor asked for it and both addresses are real.
  # The new slug mirrors HasMetadata#url_name: url_name, else the title, else
  # the file name — read from the submitted metadata, so a blanked url_name
  # (back to the title) counts.
  def add_rename_redirect(model, old_address, metadata, file_path)
    return if params[:create_redirect_from].blank? || old_address.blank?
    return unless metadata["status"].to_s.strip == "published"

    new_slug = metadata["url_name"].to_s.strip.presence ||
               metadata["title"].to_s.strip.presence&.parameterize ||
               File.basename(file_path.to_s, ".md")
    new_address = model.public_url_for(new_slug)
    return if new_address == old_address

    result = RedirectManager.add_301(from: old_address, to: new_address)
    flash[:notice] = "#{flash[:notice]}. Redirect added: #{result.from} → #{result.to}." if result.written
  end
end

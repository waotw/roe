# Shared bits of the NEW POST / PAGE / PRODUCT forms.
#
# The forms submit their short list of fields as `fields[...]`. Those go
# straight into the new file's frontmatter, so they're whitelisted against what
# the type actually declares — otherwise a hand-crafted form could set
# `status: published`, or any other key, on creation.
module CreatesContent
  extend ActiveSupport::Concern

  private

  # Blank-rejecting whitelist of the form's `fields[...]` values.
  # Posts vary by post_type; pages and products don't.
  def create_field_overrides(resource_type, post_type: nil)
    submitted = params[:fields]
    return {} unless submitted.respond_to?(:to_unsafe_h)

    allowed = create_field_names(resource_type, post_type)
    # Products sit outside the members system, so no audience for them.
    allowed << "audience" if SiteFeature.members_enabled? && resource_type != "product"

    submitted.to_unsafe_h.slice(*allowed).each_with_object({}) do |(key, value), out|
      out[key] = value.to_s.strip if value.to_s.strip.present?
    end
  end

  def create_field_names(resource_type, post_type)
    fields = if resource_type == "post"
      Post.create_fields_for_type(post_type)
    else
      ContentMetadataSchema.create_fields_for(resource_type)
    end
    fields.map { |f| f[:name].to_s }
  end
end

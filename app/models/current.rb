class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :member  # user = admin, member = public

  # Set true during StaticGenerator runs so auth helpers (current_member,
  # authenticated?) return the anonymous-visitor state regardless of
  # whose session triggered the build. Otherwise admin-only markup
  # (member icon, paywall bypass) gets baked into the static HTML.
  attribute :static_generation

  # Per-request cache of files under site/media/. Lazily populated by
  # Post.media_file_set so admin views that ask needs_attention? on many
  # posts only pay for one directory glob, not one File.exist? per ref.
  attribute :media_file_set

  # Admin helpers
  def admin?
    user.present?
  end

  # Member helpers
  def can_access_premium?
    member&.paid? && member&.active?
  end
end

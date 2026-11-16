# The theme reference pages' sample images, audio and video. They live in
# current/ (ThemeReference::MEDIA_DIR), so /media/... can't serve them: that
# route only reads site/. Same range handling as MediaController, so the audio
# and video players can seek. Signed-in admins only, like the pages.
class Admin::ThemeReferenceMediaController < MediaController
  prepend_before_action :require_authentication

  private

  def resolve_media_path(rel)
    name = File.basename(rel)
    return nil unless name == rel && ThemeReference.media_files.include?(name)

    ThemeReference::MEDIA_DIR.join(name).to_s
  end

  def protected_file?
    false
  end
end

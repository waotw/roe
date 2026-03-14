class Admin::SettingsController < Admin::BaseController
  TEMPLATE_PATH = Rails.root.join("content/templates/post_template.md")

  def edit_post_template
    @template_content = if File.exist?(TEMPLATE_PATH)
      File.read(TEMPLATE_PATH)
    else
      default_template
    end
  end

  def update_post_template
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(TEMPLATE_PATH))

    File.write(TEMPLATE_PATH, params[:content])
    flash[:notice] = "Post template updated"
    redirect_to admin_settings_post_template_path
  end

  private

  def default_template
    <<~TEMPLATE
      ---
      title:
      date: #{Date.today}
      status: draft
      post_type: article
      ---

      Start writing...
    TEMPLATE
  end
end

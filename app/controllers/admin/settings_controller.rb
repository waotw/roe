class Admin::SettingsController < Admin::BaseController
  # Content-template editors (post / page / product). The editable template
  # holds the optional default frontmatter + starter body an author can
  # customise per install. Required fields (ContentTemplate::REQUIRED) are
  # shown locked and always added to new content, so they can't be lost here.
  def edit_template
    @type = template_type
    @template_content = ContentTemplate.template_content(@type)
    @required_names = ContentTemplate.required_names(@type)
  end

  def update_template
    ContentTemplate.save_template(template_type, params[:content])
    flash[:notice] = "#{template_type.capitalize} template updated"
    redirect_to admin_settings_template_path(type: template_type)
  end

  private

  def template_type
    t = params[:type].to_s
    ContentTemplate.type?(t) ? t : "post"
  end
end

# frozen_string_literal: true

# How a content editor save answers: the editor page for an ordinary form post,
# or JSON for the editor's background save (editor_background_save.js), which
# keeps the writer's place — cursor, scroll and undo — instead of rebuilding
# the page.
#
# The background save only works for a save that changes nothing else on the
# page. Publishing, a status change, a redirect written, or anything worth a
# notice changes buttons and messages the editor doesn't redraw, so those
# answer `reload: true` and the editor loads the page as before (the notice
# rides along in the flash).
#
# The metadata panel is rendered on the server — field lists by post type,
# media warnings, unique-value checks — so when the file's metadata differs
# from what the editor sent (a podcast GUID added, a duration filled in, tags
# tidied), the answer carries the panel as the edit page would draw it and the
# editor swaps it in. When they match, the panel is left alone.
module EditorSave
  extend ActiveSupport::Concern

  private

  # record          — the post, page or product, reloaded after the write
  # resource_type   — "post", "page" or "product"
  # edit_path       — where the editor lives
  # file_path       — the file just written (absolute)
  # submitted       — the metadata hash as the editor sent it, before Roe
  #                   tidied it
  # status_before   — the record's status before the save
  def finish_editor_save(record:, resource_type:, edit_path:, file_path:, submitted:, status_before:)
    respond_to do |format|
      format.html { redirect_to edit_path }
      format.json do
        saved_yaml = editor_metadata_yaml(file_path)

        if editor_save_needs_reload?(record, status_before)
          render json: { saved: true, reload: true, url: edit_path }
        else
          changed = editor_metadata_hash(saved_yaml) != submitted
          render json: {
            saved:         true,
            reload:        false,
            url_name:      record.url_name,
            metadata_html: (render_metadata_panel(saved_yaml, resource_type, record) if changed)
          }
        end
      end
    end
  end

  # The YAML-warning path writes the file as sent and says so; the notice
  # needs the page.
  def finish_editor_save_with_warning(edit_path)
    respond_to do |format|
      format.html { redirect_to edit_path }
      format.json { render json: { saved: true, reload: true, url: edit_path } }
    end
  end

  def editor_save_needs_reload?(record, status_before)
    flash[:notice].present? || flash[:warning].present? ||
      record.status.to_s != status_before.to_s
  end

  # Read back exactly as the edit action does, so the panel matches a page load.
  def editor_metadata_yaml(file_path)
    FrontMatterParser::Parser.new(:md).call(File.read(file_path)).front_matter.to_yaml.sub(/\A---\n/, "")
  end

  def editor_metadata_hash(yaml)
    parsed = YAML.safe_load(yaml.to_s, permitted_classes: [ Date, Time, Symbol ])
    parsed.is_a?(Hash) ? parsed : {}
  rescue Psych::Exception
    {}
  end

  def render_metadata_panel(yaml, resource_type, record)
    render_to_string(partial: "shared/metadata_editor", formats: [ :html ],
                     locals: { metadata: yaml, resource_type: resource_type, item: record })
  end
end

# Settings → tags.yml. Shows the tag list with how many posts, pages,
# products and docs use each, and adds, renames and deletes tags. Renaming
# and deleting change every file that has the tag.
#
# Changes render inside the tag_manager turbo frame, so the page doesn't
# reload. They redirect back to index, which the frame follows.
class Admin::TagsController < Admin::BaseController
  layout -> { turbo_frame_request? ? false : "admin" }

  def index
    load_tags
    @notice = flash[:tag_notice]
    # Renaming onto an existing tag merges the two. That changes what the
    # other tag is on as well, so rename sends it back here to ask first.
    if params[:merge_from].present? && @usage.key?(params[:merge_to].to_s)
      @merge = { from: params[:merge_from].to_s, to: params[:merge_to].to_s }
    end
  end

  def create
    name = TagList.add!(params[:name])
    done "Added #{name}."
  rescue TagList::Error => e
    failed e.message
  end

  def rename
    from = params[:from].to_s.strip
    to = params[:to].to_s.strip
    merging = from != to && TagList.usage.key?(to)

    if merging && params[:merge] != "1"
      return redirect_to admin_tags_path(merge_from: from, merge_to: to)
    end

    changed = TagList.rename!(from, to)
    verb = merging ? "Merged #{from} into #{to}." : "Renamed #{from} to #{to}."
    done "#{verb} #{changed_files(changed)}"
  rescue TagList::Error => e
    failed e.message
  end

  def destroy
    name = params[:name].to_s.strip
    changed = TagList.delete!(name)
    done "Deleted #{name}. #{changed_files(changed)}"
  end

  private

  def load_tags
    @usage = TagList.usage
    @show_products = TagList.show_products?
    @show_docs = TagList.show_docs?
    @unused = @usage.select { |_, counts| counts.values.sum.zero? }.keys
  end

  def done(message)
    flash[:tag_notice] = message.strip
    redirect_to admin_tags_path
  end

  def failed(message)
    load_tags
    @alert = message
    render :index, status: :unprocessable_entity
  end

  def changed_files(count)
    count.zero? ? "" : "#{helpers.pluralize(count, 'file')} changed."
  end
end

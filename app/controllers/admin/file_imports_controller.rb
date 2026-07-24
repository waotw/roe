require "zip"

# File Imports — upload a ZIP of markdown/HTML (a blog export, a static site,
# a pile of notes), review the page/post split, then import everything as
# drafts. The extracted ZIP is held in tmp between the review and the import;
# both steps run through FilesImporter::Runner.
class Admin::FileImportsController < Admin::BaseController
  IMPORTS_ROOT = Rails.root.join("tmp", "file_imports")
  TOKEN_RE     = /\A[a-f0-9]{16}\z/

  def index
    @imports = Import.where(source_type: "files").order(created_at: :desc)
  end

  # Summary of a single import + its current content breakdown.
  def show
    @import = Import.where(source_type: "files").find(params[:id])
  end

  # Upload + extract + classify → render the review screen.
  def create
    upload = params.dig(:file_import, :archive)
    unless upload.respond_to?(:read)
      return redirect_to admin_file_imports_path, alert: "Choose a .zip file to import."
    end

    @token = SecureRandom.hex(8)
    dir = IMPORTS_ROOT.join(@token)
    FileUtils.mkdir_p(dir)

    begin
      extract_zip(upload, dir)
    rescue => e
      FileUtils.rm_rf(dir)
      return redirect_to admin_file_imports_path, alert: "Couldn't read that ZIP: #{e.message}"
    end

    docs = FilesImporter::Runner.new(root: dir).documents
    if docs.empty?
      FileUtils.rm_rf(dir)
      return redirect_to admin_file_imports_path, alert: "No markdown or HTML files found in that ZIP."
    end

    @posts     = docs.select { |d| d.kind == :post }
    @pages     = docs.select { |d| d.kind == :page }
    @ambiguous = docs.select { |d| d.kind == :ambiguous }
    render :preview
  end

  # Import with the reviewer's per-file choices for ambiguous files.
  def run
    dir = safe_dir(params[:token])
    unless dir
      return redirect_to admin_file_imports_path, alert: "That import expired — upload the ZIP again."
    end

    overrides = params[:kinds].is_a?(ActionController::Parameters) ? params[:kinds].to_unsafe_h : {}

    import = Import.create!(
      source_type: "files", phase: 1, status: :importing_posts,
      started_at: Time.current, configuration: { "source" => params[:source_name].presence || "ZIP upload" }
    )
    media_mode = (params[:media_mode] == "all" ? :all : :referenced)
    result = FilesImporter::Runner.new(
      root: dir, overrides: overrides, import_ref: import.id, media_mode: media_mode
    ).import
    FileUtils.rm_rf(dir)

    import.update!(
      status: :completed, completed_at: Time.current,
      stats: {
        "posts" => result.posts, "pages" => result.pages,
        "assets" => result.assets.uniq.size, "skipped" => result.skipped,
        "warnings" => result.warnings
      }
    )

    redirect_to admin_posts_path(status: "draft", sort: "updated-desc"), notice: summary(result)
  end

  # Delete an import and its DRAFT content; published content is kept for manual
  # removal (and the import stays listed until it's gone).
  def destroy
    import = Import.where(source_type: "files").find(params[:id])
    deleted = import.delete_draft_content!
    kept = import.ref_published_count

    if kept.zero?
      import.destroy
      notice = "Deleted import ##{import.id} and its #{helpers.pluralize(deleted, 'draft')}."
    else
      import.update!(status: :rolled_back)
      notice = "Deleted #{helpers.pluralize(deleted, 'draft')}. " \
               "Kept #{helpers.pluralize(kept, 'published item')} — delete those manually from Posts/Pages."
    end
    redirect_to admin_file_imports_path, notice: notice
  end

  private

  def summary(result)
    parts = []
    parts << "#{helpers.pluralize(result.posts, 'post')}" if result.posts.positive?
    parts << "#{helpers.pluralize(result.pages, 'page')}" if result.pages.positive?
    note = "Imported #{parts.presence&.join(' and ') || 'nothing'} as drafts."
    note += " Copied #{helpers.pluralize(result.assets.uniq.size, 'media file')}." if result.assets.any?
    note += " Skipped #{result.skipped} already imported." if result.skipped.positive?
    note += " #{result.warnings.size} failed — see logs." if result.warnings.any?
    note
  end

  def safe_dir(token)
    return nil unless token.to_s.match?(TOKEN_RE)
    dir = IMPORTS_ROOT.join(token)
    Dir.exist?(dir) ? dir : nil
  end

  # Extract into dest, guarding against zip-slip (entries escaping the dir).
  def extract_zip(upload, dest)
    root = File.expand_path(dest.to_s)
    Zip::File.open_buffer(upload.read) do |zip|
      zip.each do |entry|
        next if entry.directory?
        target = File.expand_path(File.join(root, entry.name))
        raise "unsafe entry path: #{entry.name}" unless target.start_with?(root + File::SEPARATOR)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, entry.get_input_stream.read)
      end
    end
  end
end

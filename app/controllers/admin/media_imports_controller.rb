# Media Imports — find external http(s) media across your content and pull it
# into the local library, rewriting the references. Downloading runs in the
# background (large audio/video); this page shows the scan and polls progress.
class Admin::MediaImportsController < Admin::BaseController
  TYPES = %w[images audio video].freeze

  def index
    @summary = MediaImporter::Scanner.summary(MediaImporter::Scanner.scan)
    @status  = MediaImportJob.status
  end

  def create
    types = Array(params[:types]).map(&:to_s) & TYPES
    if types.empty?
      return redirect_to admin_media_imports_path, alert: "Pick at least one media type to import."
    end

    # Seed a running status so the page shows progress on the redirect, before
    # the worker picks the job up.
    MediaImportJob.write_status(state: "running", step: "queued", total: 0, downloaded: 0, failed: 0, rewritten: 0)
    MediaImportJob.perform_later(types)
    redirect_to admin_media_imports_path, notice: "Importing #{types.to_sentence} in the background…"
  end

  # Polled by the status panel.
  def status
    render json: (MediaImportJob.status || { state: "idle" })
  end

  def dismiss_status
    MediaImportJob.clear_status
    redirect_to admin_media_imports_path
  end
end

module Admin::ImportsHelper
  def status_badge_class(status)
    case status.to_s
    when "pending", "uploading"
      "bg-gray-100 text-gray-800"
    when "extracting", "importing_posts", "importing_media", "importing_members", "importing_deliveries"
      "bg-blue-100 text-blue-800"
    when "completed"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    when "rolled_back"
      "bg-yellow-100 text-yellow-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  def import_has_missing_media?(import)
    missing = import.stats["missing_media"]
    missing.present? && missing.any? { |m| !m["resolved"] && !m["skipped"] }
  end

  def import_status_label(import)
    if import.status_completed? && import.completed_phases.last == 4
      import_has_missing_media?(import) ? "Complete (missing media)" : "Import Complete"
    elsif import.status_completed?
      "Phase #{import.completed_phases.last} Complete"
    else
      import.status.humanize
    end
  end

  def import_status_badge_class(import)
    if import.status_completed? && import_has_missing_media?(import)
      "bg-amber-100 text-amber-800"
    else
      status_badge_class(import.status)
    end
  end
end

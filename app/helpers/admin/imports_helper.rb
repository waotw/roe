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
end

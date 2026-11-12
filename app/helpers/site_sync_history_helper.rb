module SiteSyncHistoryHelper
  SIDE = { "to_live" => "live", "to_local" => "local" }.freeze

  # "Nov 11, 1:36 PM", with the year when it isn't this year.
  def sync_time(time)
    time = time.in_time_zone
    time.strftime(time.year == Time.current.year ? "%b %-d, %-I:%M %p" : "%b %-d, %Y, %-I:%M %p")
  end

  # The side a change wrote to: "live" or "local".
  def change_side(change) = SIDE.fetch(change[:direction], "local")

  # What a change did, for one file's log.
  def change_summary(change)
    side = change_side(change)
    case change[:kind]
    when "rewind"
      change[:undoes_at] ? "Rewound the #{sync_time(change[:undoes_at])} sync on #{side}" : "Rewound on #{side}"
    when "restore"
      change[:action] == "deleted" ? "Removed on local by a restore" : "Restored on local"
    else
      if change[:direction] == "to_live"
        change[:action] == "deleted" ? "Deleted on live" : "Sent to live"
      else
        change[:action] == "deleted" ? "Deleted on local" : "Came down from live"
      end
    end
  end

  # Where it happened: "local → live", "live → local", or the one side a
  # rewind or restore wrote to.
  def change_where(change)
    return change_side(change) if %w[rewind restore].include?(change[:kind])

    change[:direction] == "to_live" ? "local → live" : "live → local"
  end

  def history_button_class(primary: false)
    tone = primary ? "bg-blue-100 hover:bg-blue-200" : "bg-gray-100 hover:bg-gray-200"
    "inline-flex items-center px-2 py-1 border border-gray-700 #{tone} text-gray-900 font-mono text-xs rounded-xs cursor-pointer whitespace-nowrap"
  end
end

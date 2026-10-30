# The global `roe` command's registry, read from Rails.
#
# roe.sh register writes ~/.roe/installs/<name>.conf for each install on
# this machine — plain KEY=value, never sourced, see the comment block at
# the top of roe.sh. The admin only needs to answer one question with it:
# "how does this person restart *this* site from a terminal?" That is
# `roe restart` when this is the only registered site and
# `roe restart <name>` when there are several, or the old ./roe.sh
# fallback when the install was never registered.
#
# Reads only. Registration stays a shell concern.
class RoeRegistry
  Entry = Struct.new(:name, :root, :host, :port, keyword_init: true)

  def self.home
    Pathname.new(ENV.fetch("ROE_HOME", File.join(Dir.home, ".roe")))
  end

  def self.entries
    dir = home.join("installs")
    return [] unless dir.directory?

    dir.glob("*.conf").map { |f| parse(f) }.compact.sort_by(&:name)
  rescue SystemCallError
    []
  end

  # The entry for this install, matched on the registered ROOT.
  def self.current
    root = File.realpath(RoeSitePaths::ROE_ROOT) rescue RoeSitePaths::ROE_ROOT.to_s
    entries.find { |e| (File.realpath(e.root) rescue e.root) == root }
  end

  def self.registered? = current.present?

  # The exact command to type to restart this site — the only
  # site-specific thing the admin page needs.
  def self.restart_command
    entry = current
    return nil unless entry
    entries.size > 1 ? "roe restart #{entry.name}" : "roe restart"
  end

  def self.parse(path)
    values = {}
    File.foreach(path) do |line|
      key, value = line.chomp.split("=", 2)
      values[key] = value if key && value
    end
    return nil if values["NAME"].blank? || values["ROOT"].blank?

    Entry.new(name: values["NAME"], root: values["ROOT"], host: values["HOST"], port: values["PORT"])
  rescue SystemCallError
    nil
  end
  private_class_method :parse
end

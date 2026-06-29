# ManagedTools — Roe's registry of optional external tools/libraries it can
# use but doesn't bundle (libvips today; ImageMagick, ffmpeg, … later).
#
# The infrastructure is split so adding a tool is declarative:
#   * ManagedTools::Platform — detect OS + package manager, build install cmds
#   * ManagedTools::Tool     — base class: metadata + detection + packages
#   * ManagedTools::<Name>   — one subclass per tool, listed in .all below
#
# The admin Dependencies page renders .statuses; any feature that degrades
# without a tool can ask ManagedTools.find(:libvips).installed?.
module ManagedTools
  # The known tools, in display order. Add a tool = add its subclass here.
  def self.all
    [Libvips.new]
  end

  def self.find(key)
    all.find { |tool| tool.key.to_s == key.to_s }
  end

  # Fresh status snapshots for every tool (re-detects on each call so a
  # post-install re-check reflects reality).
  def self.statuses(platform = Platform.current)
    all.map { |tool| tool.status(platform) }
  end
end

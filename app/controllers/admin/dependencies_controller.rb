class Admin::DependenciesController < Admin::BaseController
  # The optional external tools Roe can use, split over two Tools pages:
  # Images & Video (libvips, ffmpeg) and Developer Tools (Stripe CLI). Each
  # shows whether the tool is installed and, when one is missing, the exact
  # install command for THIS machine's OS and package manager.
  #
  # Read-only by design: we never run installs from a web request. System
  # package installs need sudo and shouldn't be driven from a browser, so
  # the flow is "copy the command (or `roe install <tool>`), run it,
  # re-check" (re-check is just a reload — detection runs fresh each time).
  def index
    load_tools(:media)
  end

  def development
    load_tools(:development)
  end

  private

  def load_tools(group)
    @platform = ManagedTools::Platform.current
    @tools    = ManagedTools.statuses(@platform, group: group)
  end
end

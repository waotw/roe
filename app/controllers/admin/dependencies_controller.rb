class Admin::DependenciesController < Admin::BaseController
  # Lists the optional external tools Roe can use, whether each is
  # installed, and — when one is missing — the exact install command for
  # THIS machine's OS and package manager.
  #
  # Read-only by design: we never run installs from a web request. System
  # package installs need sudo and shouldn't be driven from a browser, so
  # the flow is "copy the command, run it, re-check" (re-check is just a
  # reload of this page — detection runs fresh each time).
  def index
    @platform = ManagedTools::Platform.current
    @tools    = ManagedTools.statuses(@platform)
  end
end

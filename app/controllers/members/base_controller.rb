module Members
  class BaseController < ActionController::Base
    include MemberAuthentication

    layout "site"

    # Don't include Authentication concern - that's for admins only!
  end
end

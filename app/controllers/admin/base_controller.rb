class Admin::BaseController < ApplicationController
  before_action :require_authentication
  layout "application"
end

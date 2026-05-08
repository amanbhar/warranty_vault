module Api
  module V1
    class ApplicationController < ActionController::API
      include ActionController::Cookies
      include Authentication
      include Paginatable
    end
  end
end

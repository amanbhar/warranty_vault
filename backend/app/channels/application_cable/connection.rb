# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      reject_unauthorized_connection unless current_user
      Rails.logger.info "[ActionCable] User #{current_user&.id} connected"
    end

    def disconnect
      Rails.logger.info "[ActionCable] User #{current_user&.id} disconnected"
    end

    private

    def find_verified_user
      # Try to find user from JWT token in query params or cookies
      token = extract_token_from_params || extract_token_from_cookie

      if token.present?
        payload = JwtService.decode(token)
        if payload && payload[:user_id]
          User.find_by(id: payload[:user_id])
        end
      end
    rescue => e
      Rails.logger.error "[ActionCable] Authentication error: #{e.message}"
      nil
    end

    def extract_token_from_params
      request.params[:token]
    end

    def extract_token_from_cookie
      cookies[Authentication::COOKIE_NAME]
    end
  end
end
